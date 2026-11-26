---
bump: patch
---

### Fixed

- **The foreground-wait guard no longer sends an `until` loop to the Monitor tool.** Its refusal said to "watch it with the Monitor tool", but a Monitor command also reaches Bash-matcher hooks as a Bash call, so the guard refused the very call it suggested. The message now points to Bash with `run_in_background` and says Monitor is for a stream of events, not a wait for one condition. Two captured payloads of one Monitor call, the Monitor event and its Bash twin, are test fixtures.
