---
bump: minor
---

### Added

- `/harness-ops:behavior-probes` has an `env-scrub` area: a live case and a paired control that run a real Claude Code turn with a random fake credential planted, and check whether a Bash child can read it with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` on and off. The runner gains the `plant_env` case field and `target.result_match`, which reads a tool result not of the expected shape as `inconclusive`.
