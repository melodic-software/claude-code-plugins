---
bump: minor
---

### Added

- `/discovery:research` now requires the parent to cite each accepted claim with inline Markdown links (its primary and counted corroborators, from `sources[].url`) whenever it presents findings, including a short chat recap. A local probe cites the artifact file holding its command, and a source name without its URL is not a citation. A new eval case checks it.
