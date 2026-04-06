---
name: jj-compat
description: "**REQUIRED** - Always activate FIRST on any git/VCS operations (commit, status, branch, push, etc.). If `.jj/` exists -> this is a Jujutsu (jj) repo. Essential jj workflow instructions inside."
allowed-tools: Bash(jj *)
---

# Jujutsu (jj) Version Control System

This skill helps you work with Jujutsu, a Git-compatible VCS with mutable commits and automatic rebasing.

**Tested with jj v0.37.0** - Commands may differ in other versions.

## Important: Automated/Agent Environment

When running as an agent:

1. **Always use `-m` flags** to provide messages inline rather than relying on editor prompts:

```bash
jj desc -m "message"      # NOT: jj desc
jj squash -m "message"    # NOT: jj squash (which opens editor)
```

Editor-based commands will fail in non-interactive environments.

2. **Avoid interactive commands** — `jj split -i`, `jj commit -i`, `jj resolve` open TUI/editors and will hang. Use file-based alternatives instead.

3. **Verify operations with `jj st`** after mutations (`squash`, `abandon`, `rebase`, `restore`).

## Core Concepts

### The Working Copy is a Commit

In jj, your working directory is always a commit (referenced as `@`). Changes are automatically snapshotted when you run any jj command. There is no staging area.

There is no need to run `jj commit`.

### Commits Are Mutable

**CRITICAL**: Unlike git, jj commits can be freely modified. This enables a high-quality commit workflow:

1. Use `jj new` to initialize a new, blank commit.
2. Describe your intended changes first with `jj desc -m "Message"`
3. Make your changes
4. When complete, use `jj new` to initialize a new, blank commit and begin the process again.

### Change IDs vs Commit IDs

- **Change ID**: A stable identifier (like `tqpwlqmp`) that persists when a commit is rewritten
- **Commit ID**: A content hash (like `3ccf7581`) that changes when commit content changes

Prefer using Change IDs when referencing commits in commands.

## Essential Workflow

### Starting Work: Describe First, Then Code

```bash
jj desc -m "Add user authentication to login endpoint"
# ... edit files ...
jj st
```

### Git → jj Translation

| Git | jj | Notes |
|-----|-----|-------|
| `git status` | `jj st` | |
| `git log --graph` | `jj log` | graphical by default |
| `git diff` | `jj diff` | |
| `git add` | (not needed) | auto-tracked |
| `git add . && git commit -m MSG` | `jj commit -m MSG` | |
| `git commit --amend -m MSG` | `jj describe -m MSG` | message only |
| `git commit -m MSG` | `jj describe -m MSG && jj new` | |
| `git branch` | `jj bookmark list` | |
| `git checkout -b NAME` | `jj bookmark create NAME` | |
| `git checkout NAME` | `jj edit NAME` | |
| `git push` | `jj git push` | |
| `git fetch` / `pull` | `jj git fetch` | pull = fetch + rebase |
| `git stash` | (not needed) | work auto-saved in `@` |
| `git cherry-pick` | `jj duplicate --onto DEST` | |
| `git revert` | `jj revert --onto DEST` | `--onto` required |
| `git reset --hard HEAD~1` | `jj abandon` | |
| `git reflog` | `jj op log` | operation log |
| `git blame FILE` | `jj file annotate FILE` | |

### REVSET Quick Reference

| jj | Meaning |
|-----|---------|
| `@` | working copy commit (≈ HEAD) |
| `@-` | parent commit (≈ HEAD~1) |
| `@--` | grandparent (≈ HEAD~2) |

## Viewing History

```bash
jj log               # recent commits (graphical)
jj log -p            # with patches
jj show <change-id>  # specific commit
jj diff              # working copy diff
```

## Moving Between Commits

```bash
jj new                            # new empty commit on top
jj new && jj desc -m "message"   # new commit with message
jj edit <change-id>               # edit an existing commit
jj prev -e                        # edit previous commit
jj next -e                        # edit next commit
```

## Refining Commits

### Squashing

```bash
jj squash                          # move all @-changes into parent
jj squash --from A --into B        # move from A to B
```

### Non-interactive partial commit (agent-safe)

```bash
jj commit -m "msg" foo bar         # commit specific files, rest stays in @
jj commit -m "msg" 'glob:src/**'   # fileset pattern
```

### Absorbing

```bash
jj absorb    # auto-distribute @ changes to the ancestor that last touched each line
```

### Abandoning

```bash
jj abandon <change-id>    # remove commit; descendants rebase to its parent
```

### Undoing

```bash
jj undo               # reverse last jj operation
jj redo               # re-apply undone operation
jj op log             # view all operations
jj op restore OP_ID   # restore entire repo to a previous operation's state
```

### Restoring Files

```bash
jj restore                              # discard all uncommitted changes
jj restore path/to/file.txt            # discard specific file
jj restore --from <change-id> file    # restore from specific revision
```

## Working with Bookmarks (Branches)

**Important**: bookmarks do NOT auto-advance when you create new commits — you must move them manually before pushing.

```bash
jj bookmark create my-feature -r@    # create at current commit
jj bookmark move my-feature --to @   # move to current commit
jj bookmark list                      # list all bookmarks
jj bookmark delete my-feature         # delete bookmark
jj git push -b my-feature            # push specific bookmark
```

## Workspaces

Workspaces allow multiple working copies from the same repo:

```bash
jj workspace list                        # list workspaces
jj workspace add --name NAME PATH        # create new workspace
jj workspace forget NAME                 # remove workspace (careful with default!)
```

Each workspace has its own `@` commit. `name@` refers to workspace `name`'s WC commit.

## Automatic Working Copy Advance

When `@` becomes **immutable** (e.g. after a remote merge makes the commit part of
the permanent history), jj automatically creates a new empty commit on top and
moves `@` to it. You will see:

```
Warning: The working-copy commit in workspace 'NAME' became immutable, so a new
commit has been created on top of it.
```

This is expected — simply rebase the new empty `@` to wherever you want to continue
working.

## Remote Bookmark Revsets After Branch Deletion

`remote_bookmarks(exact:"name")` returns **empty** if the remote branch has been
deleted (e.g. GitLab deletes source branches after MR merge). If a rebase command
targeting a remote bookmark fails with "No revisions found", check whether the
remote branch still exists and fall back to a local bookmark (e.g. `master`) if needed.

## Handling Conflicts

jj allows committing conflicts — resolve them later by editing files directly to remove conflict markers. Do not use `jj resolve` (interactive, will hang in agent environments).

### Rebase Conflict Cascade

**Problem**: When `jj rebase -r @ -d TARGET` produces file conflicts, jj stores them *in the target commit* (not in the rebased commit). Every other descendant of that target — including unrelated branches like `develop` — inherits the unresolved conflicts. This can break other workspaces.

**Detection**: After any rebase, check for cascade:

```bash
jj log -r 'develop::' --no-graph | grep conflict
```

If commits you didn't touch show `(conflict)`, the rebase contaminated shared history.

**Recovery**: Use `jj op restore` to revert to the pre-rebase operation:

```bash
jj op log           # find the operation just before the rebase
jj op restore OP_ID # restore repo to that state
```

This cleanly undoes the conflict markers from the target commit and all its descendants.
`jj undo` + `jj redo` will NOT fix this — redo re-applies the same rebase and re-introduces the cascade.

**Prevention**:
- Check for file overlap before rebasing a long-running branch:
  ```bash
  jj diff -r @ --summary                      # files your branch touches
  jj log -r 'OLD_BASE..develop@git' --summary  # what develop changed since your base
  ```
- If the same files appear in both, genuine conflicts exist. Rebase only when you have time to resolve them immediately.
- Rebase onto the local develop tip (`develop`) instead of `develop@git` when possible — the local tip has no further local descendants, limiting cascade damage.
- After rebasing with conflicts, resolve them in `@` before doing anything else (especially before other workspaces run any jj command).

## Restoring Files from op log

When a file was lost without going through jj commands:

```bash
# Find snapshots
jj op log --no-graph -T 'if(self.snapshot(), self.id() ++ "\n")' | while read -r op; do
  if jj --at-op="$op" file show PATH >/dev/null 2>&1; then
    jj --at-op="$op" file show PATH > PATH
    break
  fi
done
```

## Git Integration

```bash
jj git clone <url>           # clone a git repo
jj git init --colocate       # initialize jj in existing git repo
jj git fetch                 # fetch from remote
jj git push -b <bookmark>    # push bookmark to remote
```

**Note**: `jj git push` already behaves like `git push --force-with-lease` by default —
it updates the remote only if the remote's current state matches what jj last fetched.
Neither `--force` nor `--force-with-lease` are valid flags in jj. If a push is rejected
due to divergence, run `jj git fetch` first and resolve any bookmark conflicts.

## GitLab MR: develop → master — NEVER Delete the develop Branch

**CRITICAL**: When creating an MR from `develop` into `master`, the `develop` branch
**must not** be deleted after merge. `develop` is a long-lived integration branch — it
is not a feature branch.

When using `glab mr create`, ensure the MR does **not** have "Delete source branch"
enabled. If the GitLab project default deletes source branches, explicitly disable it:

```bash
glab mr create \
  --source-branch develop \
  --target-branch master \
  --remove-source-branch=false \
  ...
```

If the branch was accidentally deleted, recreate it from master:

```bash
jj bookmark create develop -r master
jj git push --bookmark develop
```

## Git Tool Integration (glab, gh, etc.)

Tools like `glab` and `gh` require a `.git` directory. In a jj workspace the `.git`
dir lives in the colocated repo root, not the workspace directory. Resolve it dynamically:

```bash
# Resolve the colocated git root (works in both regular jj repos and workspaces)
# NOTE: In a workspace, .jj/repo is a FILE with a path relative to the .jj/
# directory itself (not the workspace root). It points to the root repo's
# .jj/repo/ directory, so cd up two more levels to reach the actual repo root.
if [ -f .jj/repo ]; then
  GIT_ROOT=$(cd .jj && cd "$(cat repo)" && cd ../.. && jj root)
else
  GIT_ROOT=$(jj root)
fi

# Then prefix git-aware tools with GIT_DIR:
GIT_DIR="$GIT_ROOT/.git" glab mr create ...
GIT_DIR="$GIT_ROOT/.git" gh pr create ...
```

## Quick Reference

| Action | Command |
|--------|---------|
| Describe commit | `jj desc -m "message"` |
| View status | `jj st` |
| View log | `jj log` |
| View diff | `jj diff` |
| New commit | `jj new && jj desc -m "message"` |
| Edit commit | `jj edit <id>` |
| Squash to parent | `jj squash` |
| Auto-distribute | `jj absorb` |
| Abandon commit | `jj abandon <id>` |
| Undo | `jj undo` |
| Redo | `jj redo` |
| Restore files | `jj restore [paths]` |
| Create bookmark | `jj bookmark create <name> -r@` |
| Move bookmark | `jj bookmark move <name> --to @` |
| Push bookmark | `jj git push -b <name>` |

## Claude Code Hook: Auto `jj new` on Prompt Submit

When `@` sits directly on a remote tracking bookmark (e.g. after `jj git fetch` moves
`main@origin` to your working copy), any file edit would modify that remote state without
a proper local change. This hook detects that condition at the start of each user task
and automatically runs `jj new` so edits always land on a fresh local change.

**Why `UserPromptSubmit` (not `PreToolUse`)**: `jj log` snapshots the working copy if
there are uncommitted changes, creating one op log entry per invocation. Using
`PreToolUse` on file-edit tools would create one op log entry per file edited.
`UserPromptSubmit` fires once per user message, giving one op log boundary per task.

### Setup

1. Copy the hook script from this plugin to your project:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/hooks/ensure-jj-change.sh" .claude/hooks/
chmod +x .claude/hooks/ensure-jj-change.sh
```

2. Add to your project's `.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ensure-jj-change.sh"
          }
        ]
      }
    ]
  }
}
```

The hook is a no-op when `@` is already on a local change — it exits silently after
one fast `jj log` check.

## Best Practices

1. **Describe first**: Set the commit message before coding
2. **One change per commit**: Keep commits atomic and focused
3. **Use change IDs**: They're stable across rewrites
4. **Refine commits**: Leverage mutability for clean history
5. **Move bookmarks manually** before pushing — they don't auto-advance
