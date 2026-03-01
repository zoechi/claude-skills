---
name: vault-secret-read
description: Safely read Vault secret metadata without exposing actual values
allowed-tools: Bash(.claude/scripts/vault-exec.sh *)
---

Safely read Vault secret at $ARGUMENTS without exposing values to Claude context.

## Steps

1. Execute: `.claude/scripts/vault-exec.sh kv get -format=json $ARGUMENTS`
2. Parse JSON output to extract key names only (NOT values)
3. Show user:
   - Secret path
   - List of key names available
   - Metadata (version, created_time, etc.)
4. Inform user: "Secret exists with keys: [list]. Values not shown for security."
5. If user needs specific key value, they can:
   - Run `.claude/scripts/vault-exec.sh kv get $ARGUMENTS` manually
   - Copy the value themselves

## Example Output

For secret at `secret/ssh/production/authorized-keys`:

```
Secret: secret/ssh/production/authorized-keys
Keys: [user1, user2, root]
Version: 5
Created: 2026-01-15T10:30:00Z
Updated: 2026-02-20T14:22:00Z

ℹ️ Values not shown for security. To retrieve specific key value, run:
.claude/scripts/vault-exec.sh kv get -field=user1 secret/ssh/production/authorized-keys
```

## Security

- Wrapper script uses SOPS to decrypt credentials
- Secrets loaded in subshell, never exported to environment
- Claude only sees key names and metadata
- Actual secret values never appear in conversation history
- No risk of credentials leaking to ~/.claude/** files

## Note for Consuming Repos

This skill requires `.claude/scripts/vault-exec.sh` to be present in the project.
The `allowed-tools` path is relative and resolves to the consuming project's script at runtime.
