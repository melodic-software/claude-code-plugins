---
bump: major
---

### Changed

- Breaking: under a lowered auto-compact window, `zones.json` percentages and
  `thresholds[].at_percent` now read as percentages of that window, not of the model's window. The
  module reads the window the engine settled on (`CLAUDE_CODE_AUTO_COMPACT_WINDOW`,
  `autoCompactWindow`, or a per-model value) and, when it is smaller than the model's window,
  scales the percentage edges, the `thresholds` and the approach margin to it, so the zone no
  longer reads smart when auto-compact fires. The snapshot and the status tool publish the scaled
  edges with `bands.auto_compact_window`. Token bands are unchanged. If you pulled `zones.json`
  under a lowered window by hand, undo it: the module now scales it again.
