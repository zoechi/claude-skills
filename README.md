# claude-skills marketplace

Shared Claude Code plugin with skills for jj, Terraform, and Vault workflows.

## Installation

```bash
# Add this marketplace to Claude Code (once per machine)
claude plugin marketplace add https://gitlab.com/zoechi/claude-skills

# Install the plugin at user scope
claude plugin install claude-skills@claude-skills --scope user
```

## Plugins

### claude-skills

Skills for common infrastructure workflows:

| Skill | Description |
|-------|-------------|
| `jj-compat` | Jujutsu (jj) VCS — git→jj translation, agent-safe commands |
| `tf-import` | Generate Terraform import blocks with correct provider ID formats |
| `vault-policy-check` | Validate Vault policies against common glob pattern issues |
| `vault-secret-read` | Safely read Vault secret metadata without exposing values |

After installation, invoke skills with the `claude-skills:` prefix:
- `/claude-skills:jj-compat`
- `/claude-skills:tf-import`
- `/claude-skills:vault-policy-check`
- `/claude-skills:vault-secret-read`
