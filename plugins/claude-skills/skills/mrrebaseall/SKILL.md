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

## Step 3 — Rebase default workspace

```bash
jj rebase -r 'default@' -d 'remote_bookmarks(exact:"develop")'
```

If `default@` is already a descendant of `develop@origin`, this is a no-op.

## Step 4 — Rebase all other workspaces

For each non-default workspace listed in Step 2:

```bash
jj rebase -r '<workspace-name>@' -d 'remote_bookmarks(exact:"develop")'
```

Replace `<workspace-name>` with the actual name (e.g. `nix-config_claude`,
`nix-config_vault`).

Workspaces already up-to-date produce no output — that is expected.

## Step 5 — Show final state

```bash
jj log --limit 12
```

Confirm each workspace's change is now a child of `develop@origin`.

## Notes

- Use `remote_bookmarks(exact:"develop")` not bare `develop` — the local develop bookmark
  may lag behind origin after merges.
- Workspaces with conflicts after rebase will show `(conflict)` in `jj log`. Resolve them
  individually using `/mrmerge` or `jj resolve`.
- You cannot rebase the *current* workspace's `@` with `-r '<name>@'` syntax from within
  that workspace; use plain `jj rebase -r @ -d 'remote_bookmarks(exact:"develop")'` when
  targeting the active workspace.
- If a workspace has an undescribed commit (no description set), rebase still works; but
  before pushing, describe it first with `jj describe -m "..."`.

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant Notes section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/mrrebaseall/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
