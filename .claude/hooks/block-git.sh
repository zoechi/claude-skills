#!/usr/bin/env bash
# Block all git commands in Claude Code
# This hook prevents Claude from executing any git operations

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

# Block git commands (direct and indirect)
# Allow "jj git ..." subcommands — those are jj's own git integration, not the git CLI
if echo "$COMMAND" | grep -qE '(^|[\s;|&()]+)git(\s|$|&|;|\||\))'; then
  if ! echo "$COMMAND" | grep -qE '^\s*jj\s'; then
    echo "Blocked: git commands are not allowed. This project uses Jujutsu (jj) for version control." >&2
    exit 2
  fi
fi

# Also block subshell/eval attempts to run git (match whole-word sh/bash/eval as tokens)
if echo "$COMMAND" | grep -qE '(^|[\s;|&(]+)(sh|bash|eval)\s.*\bgit\b'; then
  echo "Blocked: git commands are not allowed. This project uses Jujutsu (jj) for version control." >&2
  exit 2
fi

exit 0
