---
bump: patch
---

### Added

- Carries the shared format and lint resolver (`lib/git-hooks/resolve-tool.sh`) and its YAML reader, which resolve a command per file from the repository's ecosystem record, then a shipped adapter, then nothing. No hook of this plugin uses them yet.
