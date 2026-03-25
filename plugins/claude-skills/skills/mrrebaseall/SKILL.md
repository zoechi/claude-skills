---
name: mrrebaseall
description: "Rebase the default workspace onto remote develop, then rebase all other jj workspaces onto the rebased default. Use when the user asks to sync all workspaces, rebase everything, or update all branches."
disable-model-invocation: true
allowed-tools: Bash(jj *), Edit
---

# Rebase All jj Workspaces onto Remote Develop

Syncs remote state, rebases the default workspace, then rebases every other workspace
onto the latest `develop@origin`.

## Step 1 — Fetch remote state

```bash
jj git fetch
```

## Step 2 — Discover all workspaces

```bash
jj workspace list
```

Output format: `<name>: <change-id> <commit-id> <description>`

Note each workspace name and its current change ID.

## Step 3 — Derive workspace root paths

```bash
WS_DIR=$(dirname "$(jj root)")          # parent of current workspace, e.g. /home/zoechi/source/workspaces
MAIN_REPO=$(cat .jj/repo | xargs -I{} dirname {} | xargs dirname)  # default workspace root
```

- Non-default workspaces live at `$WS_DIR/<name>` (siblings of the current workspace).
- The `default` workspace is at `$MAIN_REPO`.

## Step 4 — Rebase each workspace from within its directory

For the default workspace:

```bash
(cd "$MAIN_REPO" && jj rebase -r @ -d 'develop@origin')
```

For each non-default workspace (replace `<name>` with actual workspace name):

```bash
(cd "$WS_DIR/<name>" && jj rebase -r @ -d 'develop@origin')
```

For the **current** workspace (the one you are already in), run directly:

```bash
jj rebase -r @ -d 'develop@origin'
```

Workspaces already up-to-date produce no output — that is expected.

## Step 5 — Show final state

```bash
jj log --limit 12
```

Confirm each workspace's change is now a child of `develop@origin`.

## Notes

- Use `develop@origin` not bare `develop` or `remote_bookmarks(exact:"develop")` — the local
  develop bookmark may lag behind origin after merges, and `remote_bookmarks(exact:"develop")`
  fails when multiple remotes track develop (e.g. origin + a second remote).
- Workspaces with conflicts after rebase will show `(conflict)` in `jj log`. Resolve them
  individually using `/mrmerge` or `jj resolve`.
- You cannot rebase the *current* workspace's `@` with `-r '<name>@'` syntax from within
  that workspace; use plain `jj rebase -r @ -d 'develop@origin'` when targeting the active
  workspace.
- Rebase each workspace from within its directory (`cd <path> && jj rebase -r @ -d ...`)
  rather than externally (`jj rebase -r '<name>@'`). External rebase rewrites the commit
  in the object store but does **not** update the working copy on disk; the workspace later
  detects staleness and runs a reconcile op. If an active session is concurrently
  snapshotting (e.g. another Claude Code window), this creates a divergent op chain — the
  reconcile picks the rebase branch as winner and drops the live snapshot, orphaning
  uncommitted changes. Internal rebase is one atomic op: commit rewrite + working copy
  update together, no reconcile, no race window.
  Path derivation: non-default workspaces at `$(dirname "$(jj root)")/<name>`, default at
  `$(cat .jj/repo | xargs -I{} dirname {} | xargs dirname)`.
- If a workspace has an undescribed commit (no description set), rebase still works; but
  before pushing, describe it first with `jj describe -m "..."`.
- Workspaces can be stale after another workspace was recently rebased (e.g. by `/mrmerge`
  run just before). `jj rebase` fails with "The working copy is stale". Fix: run
  `jj workspace update-stale` inside that workspace's directory before rebasing. Pattern:
  `cd <path> && jj workspace update-stale && jj rebase -r @ -d 'develop@origin'`.

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant Notes section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/mrrebaseall/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
