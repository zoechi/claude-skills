#!/usr/bin/env bash
# Block all git commands in Claude Code
# This hook prevents Claude from executing any git operations

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Actionable message: redirect to the jj workflow instead of just saying "no".
read -r -d '' BLOCK_MSG <<'EOF'
Blocked: this project uses Jujutsu (jj), not git. Do NOT retry with git.
-> Invoke the `jj-compat` skill for the jj workflow, then use jj directly.
Quick map: git add/commit -> (nothing; jj auto-snapshots) . git commit -m -> jj desc -m
  git checkout -b -> jj new / jj bookmark . git push -> jj git push (allowed) . git status -> jj st
To create an MR use the `mrcreate` skill.
EOF

# Block git commands (direct and indirect)
# Allow "jj git ..." subcommands — those are jj's own git integration, not the git CLI
if echo "$COMMAND" | grep -qE '(^|[\s;|&()]+)git(\s|$|&|;|\||\))'; then
  if ! echo "$COMMAND" | grep -qE '^\s*jj\s'; then
    echo "$BLOCK_MSG" >&2
    exit 2
  fi
fi

# Also block subshell/eval attempts to run git (match whole-word sh/bash/eval as tokens)
if echo "$COMMAND" | grep -qE '(^|[\s;|&(]+)(sh|bash|eval)\s.*\bgit\b'; then
  echo "$BLOCK_MSG" >&2
  exit 2
fi

exit 0
