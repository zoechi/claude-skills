#!/usr/bin/env bash
# Ensure the current jj working copy is NOT at a remote tracking bookmark before file edits.
# If it is, automatically run 'jj new' to create a new change first.

# Drain stdin (tool input JSON — not needed for this check)
INPUT=$(cat)

# Skip if not in a jj repo
jj root &>/dev/null || exit 0

# Check if @ coincides with any remote tracking bookmark.
# remote_bookmarks() revset returns all commits that are targets of remote bookmarks.
if jj log -r "@ & remote_bookmarks()" --no-graph -T 'commit_id.short()' 2>/dev/null | grep -q .; then
    remote_bms=$(jj log -r "@" --no-graph -T 'separate(" ", bookmarks)' 2>/dev/null | tr -s ' ' | grep -o '[^ ]*@[^ ]*' | paste -sd ' ')
    echo "Current change is at remote tracking bookmark(s): ${remote_bms:-unknown}." >&2
    echo "Running 'jj new' to create a new change before editing..." >&2
    jj new >&2
    echo "New change created. Proceeding with file edit." >&2
fi

exit 0
