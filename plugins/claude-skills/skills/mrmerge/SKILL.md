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

### Filtering by approval status

When the user says **"approved MRs"** or **"all approved"**, they mean MRs where a
reviewer has clicked ✓ **Approve** in GitLab — **not** just MRs that are technically
mergeable (no conflicts, branch-protection satisfied). These are different things.

Before merging a batch of MRs, check the approval count for each:

```bash
GIT_DIR="$GIT_ROOT/.git" glab api "projects/<namespace>/merge_requests/<id>/approvals" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('approved_by', [])))"
```

- Output `0` → no approvals; **skip** this MR and report it as skipped.
- Output `≥1` → has approval(s); proceed to merge.

Apply this filter to every MR in the batch when the user's phrasing includes
"approved". Skip this check when the user lists explicit MR IDs — they are
authorising the merge directly.

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
jj git push --bookmark <feature-bookmark> --allow-new
sleep 8   # wait for GitLab to re-evaluate mergeability
```

### 3e — Retry merge

```bash
GIT_DIR="$GIT_ROOT/.git" glab mr merge <id> --squash=false --yes
```

If still failing, report the error to the user and stop.

## Step 4 — Post-merge sync

**MANDATORY**: always run `jj git fetch` here, even if Step 3 already fetched. Do not skip it.

```bash
jj git fetch
```

After fetching, verify that `develop@origin` has advanced past the pre-merge commit by
printing its current commit ID:

```bash
jj log -r 'develop@origin' --no-graph -T 'commit_id ++ "\n"'
```

If the output is the same commit ID as before the merge, the fetch did not pick up the
merge commit — stop and report the error to the user. Do not proceed with the rebase.

```bash
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
jj log -r 'empty() & mutable() & descendants(develop@origin) ~ develop@origin ~ @' --no-graph -T 'change_id ++ "\n"'
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
- The GitLab merge commit itself (e.g. "Merge branch 'fix/...' into 'develop'") shows up as `develop*` (local-only, not yet in `develop@origin`) immediately after `jj git fetch`. The clean-up query correctly includes it via `descendants(develop@origin)`. Abandoning it will delete `develop` — always restore with `jj bookmark set develop -r 'develop@origin'` and rebase `@` after abandoning.
- If `@` is still the feature commit itself when the MR merges, the fetch marks it immutable and `jj rebase -r @ -d 'develop@origin'` fails with `Commit ... is immutable` (jj's auto-advance only fires on snapshot, not on fetch). Use `jj new 'develop@origin'` instead of the rebase — it starts a fresh empty working copy on the merge commit, which is the desired end state anyway.
- The `jj git fetch` in Step 4 has been observed to be silently skipped when the model determines it is redundant (e.g. after Step 3 already fetched). This leaves `develop@origin` stale and causes the subsequent rebase to land `@` on the old pre-merge develop. The verification step (checking `develop@origin` commit ID after fetch) exists to catch this — do not remove it.
- When `@` **is** the merged branch head (working copy sits on the feature bookmark's tip, no separate empty commit on top), the post-merge fetch makes `@` an immutable ancestor of `develop@origin` and `jj rebase -r @ -d 'develop@origin'` fails with "would rewrite 2 immutable commits". Use `jj new 'develop@origin'` instead to start a fresh working-copy commit on the new develop head.
- `jj squash` (Step 3c) can fail with "Could not acquire lock for index file ... '.git/index.lock' might need manual deletion" in colocated repos. If no jj/git process is running (`pgrep -a jj`) and the lock file is zero bytes, it is stale — delete `.git/index.lock` and retry the squash.
- An approved MR can still refuse to merge with `ERROR: This merge request requires a passing pipeline before merging.` — approval and mergeability are independent gates (`detailed_merge_status: ci_must_pass` / `ci_still_running`). Check the pipeline before attempting the merge: `glab api "projects/<ns>/merge_requests/<id>" | python3 -c "import sys,json;d=json.load(sys.stdin);p=d.get('head_pipeline') or {};print(p.get('status'),d.get('detailed_merge_status'))"`, then per-job via `.../pipelines/<pid>/jobs` and `.../jobs/<jid>/trace`. Fixing CI is a separate decision from merging — ask the user before pushing fixes into someone else's MR.
- When several approved MRs are queued and one fails only on `cargo-deny` advisory drift (new RUSTSEC advisories against an older `Cargo.lock`), merge the MR that refreshes the lock / adds the `deny.toml` ignore **first**, then rebase the other onto the new develop — its `deny` job goes green without touching it.
- `jj git fetch` (and `jj git push`) can stall for 10–20 minutes and then fail with "Please make sure you have the correct access rights and the repository exists." An immediate retry succeeds in seconds. Observed twice in one session on the same remote. Do not treat the first failure as a real auth problem — retry once before diagnosing. Related: `jj` snapshotting can be slow enough that a `timeout N jj ...` wrapper kills it mid-snapshot and leaves a stale zero-byte `.jj/working_copy/working_copy.lock`; with no `jj` process running (`pgrep -x jj`) that lock is stale and safe to delete. Prefer running slow `jj` commands as background tasks over wrapping them in `timeout`.
- **The clean-up query listed two false positives after a clean merge (no conflicts), both of which would have been damaging to abandon.** `descendants(x)` *includes* `x`, so when the GitLab merge commit is empty — the normal case for a clean merge — `develop@origin` itself matched and was offered as an abandon candidate (verified with `jj log -r <id> -T remote_bookmarks`). `@` matched too, since the working copy is empty right after a rebase; abandoning it just churns a new empty `@`. The revset is now `... & descendants(develop@origin) ~ develop@origin ~ @`. Before abandoning anything from this list, confirm the commit is not `develop@origin` with `jj log -r <change-id> --no-graph -T 'remote_bookmarks'` — an empty result means it is safe.
- The post-merge `jj git fetch` can hang or fail when the SSH remote (`git@gitlab.com`) uses a YubiKey with touch-required policy and the user isn't at the machine — symptom: `git: Connection closed by <ip> port 22` / `fatal: Could not read from remote repository`. Run the fetch with `run_in_background: true` and ask the user to touch the key; when it truly succeeds you'll see `bookmark: develop@origin [updated]`. Do NOT pipe jj through `| tail` when you need its exit status — the pipe reports tail's exit (0) and masks jj's failure; run `jj git fetch; echo "EXIT=$?"` on its own line, or verify by re-reading `develop@origin`'s commit id. If the remote is SSH-only there is no non-interactive fallback — the merge is already done server-side (confirm with `glab api "projects/<ns>/repository/branches/develop"`), so the remaining sync is purely local and can wait for the user to run the fetch in their own session.
