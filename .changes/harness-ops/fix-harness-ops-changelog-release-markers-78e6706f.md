---
bump: patch
---

### Fixed

- `/harness-ops:changelog` `status`, `diff` and `apply` read the changelog page's current `**X.Y.Z**` release headings again instead of reporting `range: not computed`; the older `<Update label>` blocks still parse. One parser, `scripts/changelog-releases.sh`, now serves the status script, the `fetch` slice and the behavior-probes `recheck`.
