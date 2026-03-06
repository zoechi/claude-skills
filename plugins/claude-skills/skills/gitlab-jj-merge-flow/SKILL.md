---
name: gitlab-jj-merge-flow
description: "Merge a jj feature branch through develop into master on GitLab, then sync all local bookmarks. Use when the user asks to merge, ship, or land a feature branch."
disable-model-invocation: true
allowed-tools: Bash(jj *), Bash(glab *)
---

# GitLab + jj: Feature → Develop → Master Merge Flow

Guides a feature branch through the full merge pipeline and keeps local bookmarks
in sync. Assumes: jj VCS, GitLab remote, branching model `feature → develop → master`.

## Step 1 — Verify current state

```bash
jj log --limit 5
jj status
```

Confirm:
- The current bookmark (`@`) is the feature branch to merge
- The parent commit is on `develop`

If the working copy has uncommitted changes, note them to the user — jj will
auto-snapshot them into `@` when the push runs, so they will be included in the
MR. Proceed without pausing unless the user asks to restructure first.

## Step 1b — Verify based on latest upstream develop

Check whether `@` descends from the latest upstream develop:

```bash
jj log -r 'remote_bookmarks(exact:"develop") & ancestors(@)'
```

- If the command **returns a commit**: `@` is based on upstream develop — continue.
- If the command **returns nothing**: `@` is NOT based on upstream develop.

When `@` is not based on upstream develop, ask the user:

> "The current change is not based on the latest upstream develop. Do you want me to
> rebase onto it? (If no, the workflow will stop here.)"

If **yes**: rebase, then resolve any conflicted bookmarks:

```bash
jj rebase -d 'remote_bookmarks(exact:"develop")'
# If the feature bookmark now shows as conflicted:
jj bookmark set <feature-bookmark> -r @
```

If **no**: stop the workflow and inform the user that the feature branch must be
based on upstream develop before the merge flow can proceed.

## Step 2 — Push feature branch

```bash
jj git push --bookmark <feature-bookmark>
```

If the remote has diverged (branch shows "ahead by X, behind by Y"), push with:

```bash
jj git push --bookmark <feature-bookmark> --force-with-lease
```

Note: `glab` requires a real git directory. Run `glab` commands from the git store
root, not the jj workspace root (e.g. `cd /path/to/nix-config` before `glab` calls
when the workspace is a linked worktree).

## Step 3 — Create or update MR: feature → develop

Check for an existing MR first:

```bash
# From git store root
glab mr list --source-branch <feature-bookmark> --target-branch develop
```

If no MR exists, create one:

```bash
glab mr create \
  --source-branch <feature-bookmark> \
  --target-branch develop \
  --title "<descriptive title>" \
  --description "<summary of changes>" \
  --no-editor
```

Show the user the MR URL and **pause**:

> "MR created at <URL>. Please review, wait for CI to pass, and merge it.
> Confirm here when the MR is merged."

## Step 4 — Sync local develop

After user confirms the MR is merged:

```bash
jj git fetch
jj bookmark set develop -r 'remote_bookmarks(exact:"develop")'
```

Verify:
```bash
jj log -r 'develop'
```

## Step 5 — Create MR: develop → master

```bash
# From git store root
glab mr create \
  --source-branch develop \
  --target-branch master \
  --title "chore: merge develop into master $(date +%Y-%m-%d)" \
  --no-editor
```

Show the user the MR URL and **pause**:

> "MR created at <URL>. Please review, wait for CI to pass, and merge it.
> Confirm here when the MR is merged."

## Step 6 — Sync local master

After user confirms:

```bash
jj git fetch
jj bookmark set master -r 'remote_bookmarks(exact:"master")'
```

## Step 7 — Rebase local work onto develop

Rebase the local working copy (if it has further changes beyond what was merged):

```bash
jj rebase -d 'remote_bookmarks(exact:"develop")'
jj log --limit 5
```

Show final state to the user.

## Notes

- **glab must run from the git store root**, not the jj workspace root, when the
  workspace is a linked worktree (`.jj/repo` is a pointer file, not a directory).
  Use `jj root` to find the workspace root, then navigate to the actual git store.
- Use `jj bookmark list` to discover the correct bookmark names if in doubt.
- If `develop` and `master` are named differently (e.g. `main`), adapt accordingly.
