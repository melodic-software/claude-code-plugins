---
bump: patch
---

### Fixed

- The audit's sandbox escape-surface table now says some `excludedCommands` calls stay sandboxed. It adds a PermissionRequest hook that rewrites a command into an excluded one (2.1.328), and mods Claude writes that turn on without asking in auto and bypass modes (2.1.321). The outside-directory paragraph is re-checked against 2.1.327.
