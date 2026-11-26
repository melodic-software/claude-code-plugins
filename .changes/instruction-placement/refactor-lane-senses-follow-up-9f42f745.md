---
bump: major
---

### Changed

- **Placement findings have a direction, not a lane.** "Lane" now means only a worker that
  serves one pipeline stage, so demote and promote are directions: `scripts/detect.sh identity`
  takes `--direction demote|promote` (`--lane` is gone, with no alias), the findings artifact
  writes `**Direction:**`, and the `check` field reads `instruction-placement/audit/<direction>`
  with the same values. The delta skill's prose names it a skill.
