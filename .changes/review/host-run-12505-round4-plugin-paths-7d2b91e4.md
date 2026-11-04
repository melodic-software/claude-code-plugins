---
bump: patch
---

### Fixed

- The run-everything sweep names its workflow script (`workflows/fanout-sweep.js`), and the `doc-drift-detector` agent names the file that defines the `review.yaml` keys (`reference/config.md`), so neither searches the plugin directory with `Glob`, `Grep` or `ls` to find them. Those searches were denied in eval runs, which made the reviewer-diversity suites invalid.
