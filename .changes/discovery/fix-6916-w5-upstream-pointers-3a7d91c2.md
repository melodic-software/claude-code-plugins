---
bump: patch
---

### Fixed

- The parent contract's deny-rule pointer now names the sub-agents section on disabling specific
  subagents, and `discovery:researcher`'s `high` pin points at the section that says what overrides
  it. The explorer agent points at where the built-in `Explore` model is stated instead of asserting it, the deep tier says
  its `maxConcurrent` clamp is the plugin's own cap, and `setup` no longer says every env var waits
  for the next session, and points at where a settings-file `env` value's timing is stated
  ([#6916](https://github.com/melodic-software/claude-code-plugins/issues/6916)).
