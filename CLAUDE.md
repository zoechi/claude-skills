# CLAUDE.md — claude-skills repository

## Plugin Version

**Always bump the plugin version when pushing to remote main or creating a PR.**

The version is in `plugins/claude-skills/.claude-plugin/plugin.json`. Increment the
patch version (e.g. `1.0.4` → `1.0.5`) so that users who run `/plugin` will pick up
the updated skill content.

```json
{
  "version": "1.0.5"
}
```

Forgetting to bump the version means users will not receive updates until the version
is manually incremented in a follow-up commit.
