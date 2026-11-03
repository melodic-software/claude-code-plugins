---
bump: patch
---

### Changed

- `setup` and `sweep-all` no longer restate when Claude Code prompts for plugin options, which
  settings files it ignores, or when it renders them. They keep the rule to treat an empty or
  literal-placeholder value as unset and the fresh-session rerun, and point at the plugin manifest
  reference sections, with an as-of date and a recheck trigger.
