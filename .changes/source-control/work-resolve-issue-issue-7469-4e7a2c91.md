---
bump: minor
---

### Added

- The babysit merge gate reads the `merge.rung` names `merge` and `merge-reviewed` as the rungs `C2` and `C3`, at the same rank and with the same promotion cells, in the config, `CLAUDE_LANES_MERGE_RUNG_CAP` and `--lane-rung-cap`. `C2` and `C3` stay accepted as aliases, and the gate still reports the rung by its code ([#7469](https://github.com/melodic-software/claude-code-plugins/issues/7469)).
