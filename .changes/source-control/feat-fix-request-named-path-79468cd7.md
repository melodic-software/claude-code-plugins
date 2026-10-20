---
bump: minor
---

### Added

- The `comments --ci` review-thread tool's `check-paths` and `record` now also allow a file in a
  kept thread's `named_paths` (a same-plugin file a write-access fix request named) when it is in
  that thread's `plugins/<p>/` directory, in plain ASCII normal form, and not an instruction path.

### Fixed

- `check-paths` and `record` no longer allow a plugin's `.mcp.json`, `.lsp.json`, `.gitmodules`,
  `CODEOWNERS`, `monitors/` or `bin/`, a `hooks` or `.claude` segment with nothing after it, a
  `.bash`, `.zsh`, `.ps1`, `.cjs`, `.mts` or `.cts` file, or any path with a character outside
  ASCII letters, digits and `_@+.-` through the plugin-wide part of a thread's scope.
