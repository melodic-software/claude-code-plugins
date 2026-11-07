---
bump: patch
---

### Fixed

- `/improvement:find` names each `context/` recipe by its full `${CLAUDE_PLUGIN_ROOT}/skills/find/context/<file>.md` path and reads it with one Read, never a Glob or Grep of the plugin directory (#13768).
