# claude-skills

Shared Claude Code skills plugin for jj, Terraform, and Vault workflows.

## Skills

| Skill | Description |
|-------|-------------|
| `gitlab-jj-merge-flow` | Merge a jj feature branch through develop into master on GitLab, then sync all local bookmarks |
| `jj-compat` | Jujutsu (jj) VCS — git→jj translation, agent-safe workflow |
| `tf-import` | Generate Terraform import blocks with correct provider ID formats |
| `vault-policy-check` | Validate Vault policies against common glob pattern issues |
| `vault-secret-read` | Safely read Vault secret metadata without exposing values |

## Installation

```bash
# Install at user scope (available in all projects)
claude plugin install https://gitlab.com/zoechi/claude-skills --scope user

# Or install at project scope
claude plugin install https://gitlab.com/zoechi/claude-skills --scope project
```

## Usage

After installation, skills are available with the `claude-skills:` prefix:

- `/claude-skills:gitlab-jj-merge-flow`
- `/claude-skills:jj-compat`
- `/claude-skills:tf-import`
- `/claude-skills:vault-policy-check`
- `/claude-skills:vault-secret-read`

## Notes

### vault-secret-read

This skill requires `.claude/scripts/vault-exec.sh` to be present in the consuming project.
The script must be allowed in `.claude/settings.json`:

```json
{
  "permissions": {
    "allow": ["Bash(.claude/scripts/vault-exec.sh *)"]
  }
}
```
