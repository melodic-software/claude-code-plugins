---
bump: patch
---

### Changed

- `/work-items:setup` infers recurring candidates from the dependency manifests and lint or formatter configs a repository holds, with no list of per-ecosystem file names.
- `/work-items:scan-todos` no longer excludes `*.min.*` and `node_modules` paths from its marker scan; it excludes the paths the repository documents instead.
- The label taxonomy's `ecosystem:` axis, the agent-brief examples and the `track` sample outputs name no language or tool.
