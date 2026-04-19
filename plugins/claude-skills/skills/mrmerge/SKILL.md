---
name: mrmerge
description: "Merge an open GitLab MR (by ID or current branch), resolve conflicts if needed, then rebase @ onto remote develop. Use when the user asks to merge an MR or land a change."
disable-model-invocation: true
allowed-tools: Bash(jj *), Bash(glab *), Bash(sleep *), Bash(rm *), Bash(cat *), Bash(echo *), Edit
---

# Merge GitLab MR and Rebase @ onto Develop

`$ARGUMENTS`: optional MR ID. If omitted, the MR is found from the current branch.

## Step 1 — Resolve MR ID and git store root

Find the current bookmark:
```bash
jj log -r @ --no-graph -T 'bookmarks'
```

If `$ARGUMENTS` is not set, find the MR by source branch:
```bash
GIT_DIR="$GIT_ROOT/.git" glab mr list --source-branch <current-bookmark>
```

Find git store root (needed for all glab calls):
```bash
[ -f .jj/repo ] && GIT_ROOT=$(cd .jj && cd "$(cat repo)" && cd ../.. && pwd) || GIT_ROOT=$(jj root)
```

Note: `.jj/repo` contains a path **relative to the `.jj/` directory** (e.g. `../../../nix-config/.jj/repo`). Using `dirname`/`dirname` on this relative path yields another relative path, breaking `GIT_DIR=`. The `cd` approach resolves it to an absolute path correctly.

## Step 2 — Attempt merge

```bash
GIT_DIR="$GIT_ROOT/.git" glab mr merge <id> --squash=false --yes
```

- If this succeeds: jump to **Step 4 (post-merge sync)**.
- If it returns 405 or a "not mergeable" / conflict error: continue to Step 3.

## Step 3 — Resolve conflicts and retry

### 3a — Fetch and reset local develop

```bash
jj git fetch
jj bookmark set develop -r 'develop@origin' --allow-backwards
```

### 3b — Rebase feature branch onto updated develop

```bash
jj rebase -b <feature-bookmark> -d 'develop@origin'
```

### 3c — Resolve any conflicts

Check for conflicts:
```bash
jj log -r 'conflicts()'
jj status
```

For each conflicted file:
- Open the file, resolve the conflict markers manually.
- For files that were deleted in one side and empty/irrelevant in the other: `rm <file>`.

After resolving all conflicts:
```bash
jj squash   # squash resolution into the conflicted commit
```

Repeat until `jj status` shows no conflicts.

### 3d — Force-push and wait

```bash
jj git push --bookmark <feature-bookmark> --force-with-lease
sleep 8   # wait for GitLab to re-evaluate mergeability
```

### 3e — Retry merge

```bash
GIT_DIR="$GIT_ROOT/.git" glab mr merge <id> --squash=false --yes
```

If still failing, report the error to the user and stop.

## Step 4 — Post-merge sync

```bash
jj git fetch
jj bookmark set develop -r 'develop@origin' --allow-backwards
```

### Rebase @ onto develop

Rebase only the working-copy commit (not descendants):
```bash
jj rebase -r @ -d 'develop@origin'
```

### Clean up leftover empty commits

Empty commits from conflict resolution can be left behind. Abandon them:
```bash
jj log -r 'empty() & mutable() & descendants(develop@origin) & ancestors(@, 5)' --no-graph -T 'change_id ++ "\n"'
# For each ID shown:
jj abandon <change-id>
```

### Show final state

```bash
jj log --limit 8
```

## Notes

- `glab mr merge` returns 405 if GitLab hasn't finished evaluating mergeability after a
  force-push; the `sleep 8` covers this in most cases.
- `--squash=false` preserves individual commits; omit only if the user wants squash merge.
- After rebase, the local `develop` bookmark may lag behind `develop@origin` — always use
  `remote_bookmarks(exact:"develop")` or `develop@origin` in revsets, not bare `develop`.
- Use `jj rebase -r @` (single commit) not `-b @` (branch) to avoid rebasing descendants
  that may belong to other work.

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant Notes section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/mrmerge/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
- `glab mr merge` can return 405 even when the API reports `detailed_merge_status: mergeable`. Workaround: use `glab api --method PUT "projects/<namespace>/merge_requests/<id>/merge" --field "should_remove_source_branch=false"` to merge directly via the API.
- Never abandon empty commits that are ancestors of `develop@origin` — this deletes the `develop` bookmark and leaves `@` with multiple parents. The clean-up query now uses `descendants(develop@origin)` to exclude them. If the bookmark is accidentally deleted, restore with `jj bookmark set develop -r 'develop@origin'` then `jj rebase -r @ -d 'develop@origin'`.
