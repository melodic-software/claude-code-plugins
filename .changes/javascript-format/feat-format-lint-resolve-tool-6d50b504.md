---
bump: patch
---

### Added

- Carries the shared format and lint runner (`lib/git-hooks/resolve-tool.sh`), which picks the plugin's shipped adapter for a file its tool's own config opts in and runs it with file names as arguments; it never runs an ecosystem record's command. No hook of this plugin uses it yet.
