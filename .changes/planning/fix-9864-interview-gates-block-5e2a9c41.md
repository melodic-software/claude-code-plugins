---
bump: patch
---

### Fixed

- The interview's Gates block, in the first 20,000 bytes of its SKILL.md, now also states the confirmation gate and the Step 4 `--brief` Brief cross-check command, each pointing at its full rule. A compaction re-attaches only the start of a skill, so before this a compacted session could lose both gates ([#9864](https://github.com/melodic-software/claude-code-plugins/issues/9864)).
