---
bump: minor
---

### Changed

- The zone's percentage bands follow a lowered auto-compact window. The module reads the window
  the engine settled on (`CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `autoCompactWindow`, or a per-model
  value) and, when it is smaller than the model's window, scales the percentage edges, the
  `thresholds` and the approach margin to it, so `zones.json` percentages are of the auto-compact
  window and the zone no longer reads smart when auto-compact fires. The snapshot and the status
  tool publish the scaled edges with `bands.auto_compact_window`. Token bands are unchanged. If you
  pulled `zones.json` under a lowered window by hand, undo it: the module now scales it again.
