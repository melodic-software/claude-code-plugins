---
bump: minor
---

### Changed

- **Breaking: `/playwright:demo-video` spells out quality control.** `scripts/qc.py` is now `scripts/quality_control.py` and `reference/qc.md` is `reference/quality-control.md`. The `qc` section of `scripts/defaults.json` is now `quality_control`, so a `--config` file that overrides `qc.*` thresholds must rename that key; there is no alias for the old name. The report is written as `quality-control.json` in the quality-control output directory instead of `qc.json`.
