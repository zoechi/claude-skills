---
name: vault-policy-check
description: Validate Vault policies against common glob pattern issues
allowed-tools: Read, Grep, Bash(vault *)
context: fork
agent: Explore
---

Validate Vault policy at $ARGUMENTS.

## Validation Steps

1. Read the policy file (HCL format)
2. Check for common Vault glob pattern issues:
   - Non-trailing `*` (only works at end of path, greedy, crosses slashes)
   - Patterns like `database-*/*` (won't work - use `database-*` instead)
   - Mid-segment `+` usage (must replace full path segment between slashes)
   - Partial segment globs (not supported)
3. Test policy capabilities with `vault policy read <policy-name>` if policy is already in Vault
4. Suggest corrections using project memory glob rules
5. Report validation results with specific line numbers and fixes

## Vault Policy Glob Rules (from project memory)

- `*` only works as a TRAILING glob — it is greedy and crosses slashes
  - ✓ `database-*` matches `database-pgadmin/config`, `database-pgadmin/roles/foo`, etc.
  - ✗ `database-*/*` does NOT work — non-trailing `*` in a path segment is not supported
- `+` replaces exactly ONE full path segment (between slashes), not a partial segment
  - ✗ `database-+/*` does NOT work — `+` cannot be used mid-segment
- For "mount-per-item" patterns (e.g. `database-<name>/`): use `database-*` (trailing `*`, no slash)

## Example Issues

**Bad:**
```hcl
path "database-*/*" {
  capabilities = ["read"]
}
```

**Good:**
```hcl
path "database-*" {
  capabilities = ["read"]
}
```
