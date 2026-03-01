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

## Handling Conflicts

jj allows committing conflicts — resolve them later by editing files directly to remove conflict markers. Do not use `jj resolve` (interactive, will hang in agent environments).

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

## Best Practices

1. **Describe first**: Set the commit message before coding
2. **One change per commit**: Keep commits atomic and focused
3. **Use change IDs**: They're stable across rewrites
4. **Refine commits**: Leverage mutability for clean history
5. **Move bookmarks manually** before pushing — they don't auto-advance
