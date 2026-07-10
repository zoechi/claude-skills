---
name: mrcreate
description: "Create a single GitLab MR for all local jj changes since the last remote tracking bookmark ancestor, targeting develop. Use when the user asks to create an MR, open a merge request, or push a feature branch."
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
[ -f .jj/repo ] && GIT_ROOT=$(cd .jj && cd "$(cat repo)" && cd ../.. && pwd) || GIT_ROOT=$(jj root)
```

Note: `.jj/repo` contains a path **relative to the `.jj/` directory** (e.g. `../../../nix-config/.jj/repo`). Using `dirname`/`dirname` on this relative path yields another relative path, which silently breaks `GIT_DIR=`. The `cd` approach resolves it to an absolute path correctly.

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
- Some jj versions do not support `--allow-new` either (it errors `unexpected argument '--allow-new'` and suggests `--all`). Confirmed on jj **0.43.0**, so this is not only an "older versions" problem — do not assume the flag exists based on version alone. For a brand-new bookmark, a plain `jj git push --bookmark <name>` works without any flag; only reach for force-style pushes on divergence.
- When `@` is a *separate feature* stacked on an unrelated open-MR change (not a fix to it), do **not** squash into the parent. Detach `@` into its own sibling MR with `jj rebase -r @ -d develop@origin` (single-revision rebase is correct here — you intentionally exclude the intermediate change). Verify with `jj log -r 'develop@origin::@'` that the parent is now `develop@origin`.
- After `jj git push`, jj may create a new empty working-copy commit on top. If the user asks to amend the commit description after pushing, use `jj describe -r <bookmark-name> -m "..."` (targeting the bookmark explicitly) rather than `jj describe` (which would describe the empty `@`). Then push again with `--allow-new`.
- For linked workspaces, `.jj/repo` contains a path relative to `.jj/`, not necessarily absolute. Using `dirname`/`dirname` on a relative path gives a relative `GIT_ROOT`, breaking `GIT_DIR=`. Always resolve with: `GIT_ROOT=$(cd .jj && cd "$(cat repo)" && cd ../.. && pwd)`.
- If `@` stacks on a change that is an open MR (not yet in `develop@origin`), rebasing `@` onto `develop@origin` will conflict because the base is missing. Squash the fix into the parent instead: delete the bookmark on `@` first (`jj bookmark delete <name>`), then `jj squash` to merge `@` into parent (the parent bookmark moves automatically), update the description if needed (`jj describe -r <parent-bookmark> -m "..."`), then force-push the parent bookmark with `--allow-new`. No new MR is needed — the existing MR is updated.
- **Amending content of an already-pushed feature commit**: After `jj git push`, jj automatically creates a new empty `@` on top of the pushed commit (the pushed commit becomes immutable). If the user then asks to amend the **content** (not just the description) of the feature commit, use `jj squash --into <bookmark-name>` to move the working-copy edits **into** the feature commit before pushing again. Using only `jj describe -r <bookmark-name>` updates the description but leaves the content in `@` (the empty child), which will silently carry forward into the *next* MR as unintended changes. Note: if the project uses a `PreToolUse(Edit)` hook (ensure-jj-change.sh) rather than `UserPromptSubmit`, the hook does not fire here because `@` is already a new local commit above the pushed bookmark — only jj's built-in immutability auto-advance is at play.
- **`jj git push` hangs or fails silently (SSH key approval popup)**: a push that produces no output (or a "Broken pipe") is usually SSH key access waiting for the user's manual approval in a confirmation popup — often hidden behind another window. Commit signing triggers the same kind of popup. Do **not** diagnose or try alternatives: tell the user to check for the (possibly hidden) approval dialog (alt-tab) and simply wait for them to confirm or deny — a denial produces a clear error output to proceed from.
- **`--allow-new` not recognized (jj 0.42.0, 0.43.0)**: `jj git push --bookmark <name> --allow-new` fails with `error: unexpected argument '--allow-new'`. Since jj 0.42.0 new bookmarks are pushed by default, so plain `jj git push --bookmark <name>` works for both new and diverged bookmarks — just drop the flag.
- `glab api --method POST ... --input <file>` fails with `{"error":"The provided content-type '' is not supported."}` / `HTTP 415` — glab does not set a content-type for `--input`. Add `--header "Content-Type: application/json"` explicitly. Building the payload with a Python heredoc and writing it to a file also avoids the shell-injection footgun of backticks in MR descriptions.
- A pre-push hook may reject `jj git push` with "nix fmt detected formatting errors — run 'just fmt'". After running `just fmt`, re-check `jj diff --stat` before pushing: the fmt normalization can make a file identical to its parent again (e.g. nvfetcher rewrites `generated.json` with 4-space indent but no content change; fmt restores 2-space, and the file drops out of the diff). Adjust the commit description if part of the change evaporated.
- Step 1's `develop@origin::@` is **empty** when `@` descends from a commit that was merged into `develop` via a merge commit (e.g. `@` sits on an already-merged `update-flake-inputs-*` branch): the merged commit is an ancestor of the new `develop@origin`, so `::` yields nothing. Use `develop@origin..@` (commits reachable from `@` but not `develop@origin`) to list the local stack after `jj git fetch`.
- If `@` mixes the MR's change with unrelated in-progress work (e.g. a `flake.lock` bump from `just upgrade` that the MR must not carry), split it non-interactively instead of putting everything in the MR: `jj split -r @ -m "<msg>" <paths...>` puts the listed paths in the first commit and leaves the rest in `@`; then `jj rebase -s <first> -d develop@origin` rebases both and the bookmark goes only on the first commit. Interactive `jj split -i` hangs.
- A pre-push `nix fmt` hook can reject a push even when `just fmt` then reports "0 changed" and `nix fmt -- --fail-on-change` exits 0; simply retrying the push succeeded.

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant Notes section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/mrcreate/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
- **`--allow-new` removed in newer jj** (observed with jj 0.42.0): `jj git push --allow-new` fails with `unexpected argument '--allow-new'`. Newer jj pushes new bookmarks by default — just run `jj git push --bookmark <name>` without the flag; only fall back to `--allow-new` on older versions that reject pushing new bookmarks.
