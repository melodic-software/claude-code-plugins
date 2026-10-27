---
bump: minor
---

### Added

- **`/session-flow:audit-sessions correction`, a judged correction lens ([#5928](https://github.com/melodic-software/claude-code-plugins/issues/5928)).** The session's own model judges each short turn the collector flagged as a correction or not, reading the excerpts as untrusted data. `sweep.py --correction-candidates` prints those excerpts with a stable `turn_id`, and `sweep.py --judged <file>` merges the verdicts into a separate `Judged (unranked)` section whose findings carry `"confidence": "judged"`. They never enter the measured findings, suggestions or exit code, and no agreement figure exists yet. The skill deletes the verdict file after the merge, and `--judged` refuses `--write-report`, so no saved report holds an excerpt.
