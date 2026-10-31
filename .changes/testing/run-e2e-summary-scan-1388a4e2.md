---
bump: patch
---

### Fixed

- **run-e2e:** `e2e-summary.json`'s `publishable` list is no longer always empty. It takes the
  paths from the `publishable` list in each drive run's `report.json`, then adds
  `e2e-summary.json` only when a scan of its text finds no hit. The scan uses the same sources as
  `/app-control:drive`'s "Mask post-check": the control skill hub's `## Mask` `values:` and the
  generic credential pattern. A hit or an unresolved value source keeps the summary out
  ([#11388](https://github.com/melodic-software/claude-code-plugins/issues/11388)).
