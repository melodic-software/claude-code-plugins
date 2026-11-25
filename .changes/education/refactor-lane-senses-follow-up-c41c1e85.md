---
bump: major
---

### Changed

- **The shared view resolver takes `--producer`, not `--lane`.** "Lane" now means only a worker
  that serves one pipeline stage, so a skill or plugin registered with the resolver is a producer:
  run `view-settings.mjs resolve --producer <id>` (`--lane` is gone, with no alias). The registry
  exports `PRODUCERS` and `producerOf`, `resolveMedium` takes `producer`, and the view builder's
  `render` takes a producer id.
- The README calls `explain` and `illustrate` the two one-shot skills, not lanes.
