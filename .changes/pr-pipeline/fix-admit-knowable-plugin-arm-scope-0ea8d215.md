---
bump: minor
---

### Changed

- Intake admission also takes issues whose Uncertainty is Knowable (`admission-rules.json`), which the run lane already runs research-first (owner decision 2026-10-24, amending Q51 criterion 3).

### Fixed

- The address-feedback scope rule (`thread-scope.mjs`) no longer lets a fix edit a plugin's control or instruction files through the plugin-wide arm; it excludes the same control paths the pull-request-files arm does.
