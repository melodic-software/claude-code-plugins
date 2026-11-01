---
bump: minor
---

### Added

- `check-skill.sh` check 30 WARNs when a SKILL.md is above the 5,000-token router cap, estimated
  from the whole file at 4 characters per token, and prints the estimate as INFO otherwise. The
  WARN never fails the run
  ([#11955](https://github.com/melodic-software/claude-code-plugins/issues/11955)).
