---
name: tf-import
description: Generate Terraform import blocks with correct provider ID formats
allowed-tools: Bash, Read, Write, Grep
---

Generate import block for resource $ARGUMENTS.

## Steps

1. Parse resource address: `resource_type.resource_name["key"]` or `module.name.resource_type.resource_name`
2. Detect provider from resource type prefix
3. Lookup correct import ID format from project memory
4. Ask user for the import ID value (or construct it if obvious)
5. Generate import block in import.tf
6. Show user the import block for review
7. Ask if they want to run terraform plan to test import

## Import ID Formats (from project memory)

### Vault provider (hashicorp/vault ~5)

- `vault_auth_backend`: just the mount path → `"approle"`
- `vault_mount`: just the mount path → `"secret"`
- `vault_database_secrets_mount`: just the mount path → `"database-grafana"`
- `vault_approle_auth_backend_role`: full path WITH `auth/` prefix → `"auth/approle/role/grafana-app"`
  - NOT `approle/grafana-app` (missing /role/ separator → "no backend found")
  - NOT `approle/role/grafana-app` (missing auth/ prefix → "no backend found")
  - CORRECT: `auth/approle/role/<role_name>`

### Consul provider (hashicorp/consul ~2)

- `consul_acl_policy`: requires UUID (not name) → `"d3646f3e-06c4-d431-377c-10a344d98b25"`
  - Get UUID: `consul acl policy list -format=json | jq '.[] | select(.Name=="policy-name") | .ID'`
- `consul_acl_token`: accessor_id UUID → `"5702f26b-588b-96a1-0ba3-e0bd30ce7327"`

### PostgreSQL provider (cyrilgdn/postgresql ~1)

- `postgresql_role`: just the role name → `"vault_admin_postgres_zburbach_eu"`

## Example Output

For `vault_mount.secret`:

```hcl
import {
  to = vault_mount.secret
  id = "secret"
}
```

For `vault_approle_auth_backend_role.grafana_app`:

```hcl
import {
  to = vault_approle_auth_backend_role.grafana_app
  id = "auth/approle/role/grafana-app"
}
```
