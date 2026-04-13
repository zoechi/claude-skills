---
name: mrcreate
description: "Create a single GitLab MR for all local jj changes since the last remote tracking bookmark ancestor, targeting develop. Use when the user asks to create an MR, open a merge request, or push a feature branch."
disable-model-invocation: true
allowed-tools: Bash(jj *), Bash(glab *), Bash(cat *), Bash(echo *), Edit
---

# Create GitLab MR for Current jj Change

Creates and pushes **all local changes since the last remote tracking bookmark ancestor**
as a **single MR** targeting `develop`, unless the user explicitly asks for separate MRs.

## Step 1 — Identify the range of changes to include

Find the topmost local change (`@`) and the nearest remote tracking ancestor:

```bash
jj log -r 'develop@origin::@' --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"'
```

This lists all commits from `develop@origin` (exclusive) up to `@` (inclusive). All of
these will be included in the single MR branch. The **topmost commit (`@`) is the MR tip**.

If the user has explicitly asked for separate MRs (e.g. "create MRs for each change"),
create one bookmark per commit and one MR each — skip to Step 2 for each.

## Step 2 — Ensure the tip change has a description

```bash
jj log -r @ --no-graph -T 'description'
```

If the output is empty, infer a description from the diff:

```bash
jj diff --stat
```

Derive a short imperative summary from the changed file paths (e.g.
`nix/shells/*.nix` + `flake.nix` → `"extract devShells into separate files"`).
Then set it automatically:

```bash
jj describe -m "<derived description>"
```

Do **not** stop or ask the user — proceed directly to Step 3.

## Step 3 — Find or create a bookmark on @

```bash
jj log -r @ --no-graph -T 'bookmarks'
```

If no bookmark is shown, derive a name from the tip change description's first line:
- Lowercase, replace spaces/special chars with hyphens, strip leading `feat:`/`fix:`/`chore:` prefixes, truncate to ~50 chars.
- Example: `"feat: add grafana dashboard"` → `add-grafana-dashboard`

Then create it automatically (no need to ask the user — it will be deleted after merge):

```bash
jj bookmark create <derived-name> -r @
```

## Step 4 — Sync with remote before pushing

Fetch remote state and rebase the full local stack onto the latest develop **before**
pushing. This prevents `jj git push` from doing an implicit fetch+rebase during the
push, which can leave files stranded in `@` instead of the pushed commit.

Use `-s` (subtree rebase) starting from the **first local change** after
`develop@origin`, not `-r @` (single-revision rebase). `-r @` replaces `@`'s parent
with `develop@origin`, severing any intermediate stacked changes and turning a
sequential stack into a parallel change.

```bash
jj git fetch
# Rebase the full local stack (from first local change) onto latest develop@origin
FIRST_LOCAL=$(jj log -r 'develop@origin::@ ~ develop@origin' --no-graph -T 'change_id.short() ++ "\n"' | head -1)
jj rebase -s "$FIRST_LOCAL" -d develop@origin
```

If `@` is already up to date the rebase is a no-op.

## Step 5 — Push the bookmark

```bash
jj git push --bookmark <name>
```

If the push fails because the remote has diverged (ahead/behind), push with force.
Note: `jj git push` does **not** support `--force` or `--force-with-lease`; use `--allow-new` instead:

```bash
jj git push --bookmark <name> --allow-new
```

After pushing, verify that the bookmark and `@` still point to the same commit (a
divergence here means the push triggered an unexpected rebase):

```bash
jj log -r "<name>" -r @ --no-graph -T 'change_id ++ " " ++ commit_id ++ "\n"'
# Both lines should have the same change_id and commit_id
```

If they differ, update the bookmark and push again:

```bash
jj bookmark set <name> -r @
jj git push --bookmark <name> --allow-new
```

## Step 6 — Find the git store root

jj workspaces can be linked worktrees where `.jj/repo` is a pointer file, not a
directory. `glab` needs real git context:

```bash
[ -f .jj/repo ] && GIT_ROOT=$(dirname $(dirname $(cat .jj/repo))) || GIT_ROOT=$(jj root)
```

Note: `.jj/repo` in a linked workspace contains a path like `/path/to/repo/.jj/repo` — two `dirname` calls are needed to reach the actual repo root (first strips `repo`, second strips `.jj`).

## Step 7 — Check for an existing MR

```bash
GIT_DIR="$GIT_ROOT/.git" glab mr list --source-branch <name>
```

If an MR already exists, print the URL and stop — no duplicate needed.

## Step 8 — Create the MR

Derive a title from the change description if not provided:

```bash
GIT_DIR="$GIT_ROOT/.git" glab mr create \
  --source-branch <name> \
  --target-branch develop \
  --title "<description from jj log>" \
  --description "<more detail if available>" \
  --no-editor
```

Print the MR URL to the user.

## Notes

- Do **not** use `--remove-source-branch` / `-d` unless the user explicitly asks; some
  workflows keep the branch for tracking.
- `--delete-source-branch` does not exist in all glab versions; use `-d` or
  `--remove-source-branch`.
- If the push fails with "no bookmark to push", ensure the bookmark was created in Step 2.
- `jj git push` does not support `--force` or `--force-with-lease`; use `--allow-new` for force-style pushes.
- After `jj git push`, jj may create a new empty working-copy commit on top. If the user asks to amend the commit description after pushing, use `jj describe -r <bookmark-name> -m "..."` (targeting the bookmark explicitly) rather than `jj describe` (which would describe the empty `@`). Then push again with `--allow-new`.
- For linked workspaces, `cat .jj/repo` returns a path like `/path/to/repo/.jj/repo`. The git root is `/path/to/repo`, so use: `GIT_ROOT=$(dirname $(dirname $(cat .jj/repo)))`.
- If `@` stacks on a change that is an open MR (not yet in `develop@origin`), rebasing `@` onto `develop@origin` will conflict because the base is missing. Squash the fix into the parent instead: `jj squash -u`, then force-push the parent bookmark with `--allow-new`. No new MR is needed — the existing MR is updated.

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant Notes section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/mrcreate/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
