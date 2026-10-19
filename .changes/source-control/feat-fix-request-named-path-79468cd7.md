---
bump: minor
---

### Added

- The `comments --ci` review-thread tool's `check-paths` and `record` now also allow a file in a
  kept thread's `named_paths` (a same-plugin file a write-access fix request named) when it is in
  that thread's `plugins/<p>/` directory, in plain ASCII normal form, and not an instruction path.

### Fixed

- `check-paths` and `record` no longer allow a plugin's `.mcp.json`, `.gitmodules` or
  `CODEOWNERS` through the plugin-wide part of a thread's scope.
