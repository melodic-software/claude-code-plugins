---
bump: patch
---

### Added

- Outcome eval cases for `blindspot`, `check`, `explore`, `read-docs`, `research` and `trace-intent`, and held-out triggering probes under `probes/` ([#6557](https://github.com/melodic-software/claude-code-plugins/issues/6557)).

### Changed

- **`blindspot`, `explore`, `trace-intent`:** shorter skill bodies with the same directives, measured against the previous text on Opus and Sonnet with no loss beyond the 0.05 margin ([#6557](https://github.com/melodic-software/claude-code-plugins/issues/6557)).
