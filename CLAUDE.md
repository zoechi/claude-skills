# CLAUDE.md — claude-skills repository

## Plugin Version

**Always bump the plugin version before creating a PR.**

The version is in `plugins/claude-skills/.claude-plugin/plugin.json`. Increment the
patch version (e.g. `1.0.2` → `1.0.3`) so that users who run `/plugin` will pick up
the updated skill content after merging.

```json
{
  "version": "1.0.3"
}
```

Forgetting to bump the version means users will not receive updates until the version
is manually incremented in a follow-up PR.
