---
name: jj-cleanup-orphans
description: "Clean up orphan and divergent jj changes: abandon empty no-description changes, resolve stale divergent versions, and delete conflicted merged-branch bookmarks. Also covers hook configuration to prevent future orphans."
allowed-tools: Bash(jj *)
---

# jj Orphan Change Cleanup

Cleans up three classes of junk that accumulate in jj repositories:

1. **Orphan empty changes** — empty, no-description commits with no bookmark and no
   meaningful children. Created when a `jj new` in a skill or workflow bypasses a
   hook-created change, or when a session ends without editing anything.

2. **Stale divergent changes** — the non-remote (`○`) version of a commit whose
   change_id appears twice. Typically created when `jj git fetch` imports a
   new version of a previously-known commit (e.g. a GitLab merge commit that was
   re-based), leaving the old local version divergent.

3. **Conflicted merged-branch bookmarks** — local bookmarks marked `(conflicted)`
   with `@origin (not created yet)`, meaning the remote branch was deleted after the
   MR was merged but the local bookmark was never cleaned up.

---

## Step 1 — Identify what needs cleaning

```bash
# Show orphan empty changes (excluding root, current @, and other workspace WC commits)
jj log -r 'empty() & description(exact:"") & mutable() & ~@ & ~working_copies()' --no-graph

# Show all divergent changes
jj log -r 'divergent()' --no-graph -T 'change_id.short() ++ " " ++ commit_id.short() ++ " " ++ description.first_line() ++ "\n"'

# Show conflicted bookmarks
jj bookmark list --all | grep conflicted
```

---

## Step 2 — Abandon orphan empty changes

```bash
jj abandon -r 'empty() & description(exact:"") & mutable() & ~@ & ~working_copies()'
```

This is safe: these changes have no content, no description, and no bookmark. If jj
warns about children, inspect with `jj log -r 'children(<change-id>)'` before proceeding.

---

## Step 3 — Abandon stale divergent changes

Divergent changes appear in pairs. The immutable (`◆`) version is the authoritative
remote copy; the mutable (`○`) version is the stale local copy to abandon.

```bash
jj abandon -r 'divergent() & mutable() & ~@'
```

Verify nothing unexpected was abandoned:

```bash
jj log -r 'divergent()' --no-graph
```

Any remaining divergent changes are immutable (on remote bookmarks) and should be
left alone.

---

## Step 4 — Delete conflicted merged-branch bookmarks

Conflicted local bookmarks with `@origin (not created yet)` are stale pointers to
feature branches whose MRs have already merged and whose remote branches have been
deleted.

**Verify the content is in develop first** — check at least one commit hash from the
bookmark listing:

```bash
# For a bookmark named "my-feature" that shows commit abc123:
jj log -r 'abc123 & ancestors(develop@origin)' --no-graph -T 'commit_id.short()'
# Non-empty output means it IS in develop — safe to delete
```

Then delete:

```bash
jj bookmark delete <bookmark-name>
# Repeat for each conflicted bookmark
```

---

## Step 5 — Verify

```bash
# All three should be empty (or only show @):
jj log -r 'empty() & description(exact:"") & mutable() & ~@ & ~working_copies()' --no-graph
jj log -r 'divergent() & mutable()' --no-graph
jj bookmark list --all | grep conflicted
```

---

## Preventing orphan changes: hook placement

### Root cause

The most common source of orphan empty changes is a `UserPromptSubmit` hook that runs
`jj new` before every prompt. This fires before the model processes the message — and
therefore before any `jj new` the workflow itself runs to position `@`. The result:
two sibling empty changes are created, and the hook's is bypassed and orphaned.

**Example** (with `UserPromptSubmit` hook):

```
[UserPromptSubmit fires]
  → hook: @ == develop@origin → jj new → creates empty change X

[Skill/workflow runs jj new develop@origin to start feature]
  → creates change Y as sibling of X
  → edits land in Y

Result: X is empty, no bookmark, no children → orphaned
```

### Fix: use PreToolUse(Edit/Write/NotebookEdit)

Registering the hook on `PreToolUse` for file-editing tools fires it **after** any
positioning `jj new` the workflow already ran. When `@` is already on a local
(non-remote) change, the hook's `@ & remote_bookmarks()` check returns empty and it
exits immediately — no new change created, no orphan.

**Example** (with `PreToolUse` hook):

```
[Skill/workflow runs jj new develop@origin]
  → creates change Y, @ is now at Y (not a remote bookmark)

[First Edit tool call fires]
  → PreToolUse hook: @ & remote_bookmarks() is empty → no-op
  → edit lands in Y ✓
```

The hook still acts as a safety net: if something leaves `@` at a remote bookmark
when the first file edit fires, it creates a `jj new` at that moment.

**Trade-off**: `jj log` inside the hook snapshots the working copy when uncommitted
changes exist, creating one op log entry per file-edit tool call (instead of one per
user message with `UserPromptSubmit`). In practice this is minor — the hook check is
a fast no-op whenever `@` is not at a remote bookmark.

### settings.json configuration

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ensure-jj-change.sh" }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ensure-jj-change.sh" }
        ]
      },
      {
        "matcher": "NotebookEdit",
        "hooks": [
          { "type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/ensure-jj-change.sh" }
        ]
      }
    ]
  }
}
```

### Other sources of orphans

- **Workflows with explicit `jj new` calls**: Any skill or workflow that calls `jj new`
  to position `@` on a specific parent will bypass a hook-created change if the hook
  fired first. `PreToolUse` placement eliminates this conflict.

- **`jj git fetch` creating divergent merge commits**: When GitLab merges an MR, it
  creates a merge commit. If jj had previously imported a version of that commit (with
  the same change_id), the newly fetched version diverges. The stale local copy
  becomes an orphaned divergent version. Clean these up with Step 3 above after every
  fetch-heavy session.

- **Automatic working-copy advance**: When `@` becomes immutable (e.g. after a push
  makes the commit remote-tracked), jj automatically creates a new empty `@` on top.
  If the session ends without using that empty `@`, it becomes an orphan. Run Step 2
  periodically to clear these.

---

## Self-update

If you encounter an edge case, failure, or workaround not documented above, append a
bullet to the relevant section of the **source** file using `Edit` before finishing:

`~/source/claude-skills/plugins/claude-skills/skills/jj-cleanup-orphans/SKILL.md`

Do **not** edit the installed copy under `~/.claude/`. Keep additions factual: what
failed, what fixed it. Do not restructure existing content.
