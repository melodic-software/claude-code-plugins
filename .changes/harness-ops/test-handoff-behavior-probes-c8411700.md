---
bump: minor
---

### Added

- `/harness-ops:behavior-probes` judges a `transcript-grep` case against its session transcript and its hooks' log: regexes matched in order, regexes that must not match, and a required PostCompact record for compaction cases.
- Probe cases for a typed `/goal` reaching UserPromptSubmit, PreCompact text steering automatic and manual compaction, a no-tool reply under an unmeetable goal, UserPromptSubmit context on a `/goal` turn, and a self-paced `/loop` wake-up in the CronList listing across a compaction.
