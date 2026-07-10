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
   - **Exact path in one policy shadowing a glob in another** — see "Policy
     precedence" below. Check every policy attached to the same role/token
     together, not just the one file in isolation.
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

## Policy precedence — capabilities do NOT union across specificity

Vault picks the **single most specific matching rule** and uses only its
capabilities. An exact path match beats a trailing glob; capabilities from the
two are **not merged**. This bites when a token carries several policies that
each mention the same path at different specificity.

Real example (2026-07-31, nix-config MR !322): the cert issuer host had both

```hcl
# cert-publish
path "certificates/data/wildcard/*"            { capabilities = ["create", "update", "read"] }
# cert-wildcard-zburbach-read
path "certificates/data/wildcard/zburbach.eu"  { capabilities = ["read"] }
```

The exact rule shadowed the glob on precisely the write target, so writes failed
with `permission denied` while the parent prefix still reported write access:

```
vault token capabilities certificates/data/wildcard/zburbach.eu   # -> read
vault token capabilities certificates/data/wildcard/              # -> create, read, update
```

That asymmetry is the fingerprint: **broad prefix shows write, specific path
shows read** means shadowing, not a missing policy attachment.

Fix: don't attach the narrow read policy to a role that already has the broader
write policy — a glob granting `create/update/read` covers reads too.

Diagnostic order when a write 403s despite the policy looking right:
1. `vault token lookup -format=json | jq -r '.data.policies[]'` — is it attached at all?
2. `vault token capabilities <exact path>` vs `<parent prefix>` — asymmetry ⇒ shadowing
3. Only then suspect a stale token (Vault Agent renews tokens *without* refreshing
   policies; `rm` the sink file and restart to force a fresh login)

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

## Never infer the API path from the CLI flag

A policy must grant the path the request actually hits, and that is often not what the
command suggests. `vault plugin reload` is the worst offender observed so far — the API
documents two endpoints (`sys/plugins/reload/backend` and
`sys/plugins/reload/<type>/<name>`), but on a real cluster **both** CLI forms hit the
`unknown` variant:

| Command | Actual request path |
|---|---|
| `vault plugin reload -plugin=<name>` | `sys/plugins/reload/unknown/<name>` |
| `vault plugin reload -mounts=<mount>/` | `sys/plugins/reload/unknown` |

An exact-path grant on `sys/plugins/reload/backend` matched neither and returned 403 for
both. Use `path "sys/plugins/reload/*"` with `["update", "sudo"]`.

Same class of error with named sub-paths: a grant on `github/token` does **not** match
`github/token/sandbox`, because the permission-set name is a path segment rather than a
request parameter. Needed `github/token/*`.

**Rule:** when a grant 403s, read the request URL out of the error message — the Vault CLI
prints it — and match the policy to *that*, rather than reasoning from the flag name or the
docs' endpoint list. Three consecutive policy bugs in one project came from skipping this.
