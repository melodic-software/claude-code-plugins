---
bump: patch
---

### Changed

- `comments --ci` records `INCORRECT` on a security-review `manifest dependencies: flag` when each entry is a bare name of another plugin in the repository's own `.claude-plugin/marketplace.json` and the flagged plugin cannot work without it. The reply cites, for each entry, a line in the flagged plugin that invokes `/<entry>:`. When any entry is optional (presence-gated, with a fallback), it records `UNCERTAIN`.
