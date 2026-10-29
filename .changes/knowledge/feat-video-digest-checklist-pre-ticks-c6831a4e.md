---
bump: minor
---

### Added

- `/knowledge:video-digest`: `init-watch-checklist.js` now ticks the Phase 1 rows the CLI already proved, and writes an evidence line under each one naming the fact it read. Row 1.1 is ticked when `watch.json` is present. Row 1.3 is ticked when `selection.json` frame, sheet and densification counts match the `watch.json` metrics. Row 1.4 is ticked when the `tempSession` directories exist on disk, 1.5 when `highVolume` matches the sheet, duration and densification rule, and 1.6 when acquire, transcript, watching and harvest are complete. When the slice has no `source/companion-sources.md`, the Phase 0b rows arrive ticked as n/a. That n/a state is recomputed on every run, so a rerun after the brief appears unticks those rows. Rows 0.1-0.4 and 1.2 stay hand-ticked.
