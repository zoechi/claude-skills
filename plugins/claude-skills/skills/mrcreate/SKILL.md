---
name: mrcreate
description: "Create a GitLab MR for the current jj change targeting develop. Use when the user asks to create an MR, open a merge request, or push a feature branch."
disable-model-invocation: true
allowed-tools: Bash(jj *), Bash(glab *), Edit
---

# Create GitLab MR for Current jj Change

Creates and pushes the current change as a GitLab MR targeting `develop`.

## Step 1 — Verify current change has a description

```bash
jj log -r @ --no-graph -T 'description'
```

If the output is empty, **stop** and ask the user to describe the change:

> "The current change has no description. Please describe it first with:
> `jj describe -m \"your description here\"`"

## Step 2 — Find or create a bookmark on @

```bash
jj log -r @ --no-graph -T 'bookmarks'
```

If no bookmark is shown, derive a name from the change description's first line:
- Lowercase, replace spaces/special chars with hyphens, strip leading `feat:`/`fix:`/`chore:` prefixes, truncate to ~50 chars.
- Example: `"feat: add grafana dashboard"` → `add-grafana-dashboard`

Then create it automatically (no need to ask the user — it will be deleted after merge):

```bash
jj bookmark create <derived-name> -r @
```

## Step 3 — Sync with remote before pushing

Fetch remote state and rebase `@` onto the latest develop **before** pushing. This
prevents `jj git push` from doing an implicit fetch+rebase during the push, which can
leave files stranded in `@` instead of the pushed commit.

```bash
jj git fetch
jj rebase -r @ -d develop@origin
```

If `@` is already up to date the rebase is a no-op.

## Step 4 — Push the bookmark

```bash
jj git push --bookmark <name>
```

If the push fails because the remote has diverged (ahead/behind), push with force:

```bash
jj git push --bookmark <name> --force-with-lease
```

After pushing, verify that the bookmark and `@` still point to the same commit (a
divergence here means the push triggered an unexpected rebase):

```bash
jj log -r "<name>" -r @ --no-graph -T 'change_id ++ " " ++ commit_id ++ "\n"'
# Both lines should have the same change_id and commit_id
```

If they differ, force-push the updated `@` to the bookmark:

```bash
jj bookmark set <name> -r @
jj git push --bookmark <name> --force-with-lease
```

## Step 5 — Find the git store root

jj workspaces can be linked worktrees where `.jj/repo` is a pointer file, not a
directory. `glab` needs real git context:

```bash
# If .jj/repo is a plain file (linked workspace):
GIT_ROOT=$(cat .jj/repo)
# If .jj/repo is a directory (default workspace):
GIT_ROOT=$(jj root)
```

Check: `[ -f .jj/repo ] && GIT_ROOT=$(dirname $(cat .jj/repo)) || GIT_ROOT=$(jj root)`

Note: `.jj/repo` in a linked workspace contains a path like `/path/to/repo/.jj/repo` — use `dirname` to get the actual git root, not the `.jj/repo` subdirectory itself.

## Step 6 — Check for an existing MR

```bash
GIT_DIR="$GIT_ROOT/.git" glab mr list --source-branch <name>
```

If an MR already exists, print the URL and stop — no duplicate needed.

## Step 7 — Create the MR

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

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant Notes section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/mrcreate/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
