---
bump: minor
---

### Added

- `observer_request_check` (off by default) adds a `request` category to the live checks: a skipped or unanswered part of the person's latest request, or work drifting from the goal the session stated.
- With `observer_harness_check` on, a scripted loop check reports a tool (a Bash command by its first two words) that fails `observer_loop_repeat` times in a row with the same error, once per tool and error; `0` turns it off. It calls no model.
- Observer usage rows record the finding's `category` on a `shown` check row and a `refused` gate row, and `held` on a `stale` row, saying whether the late reply carried a finding.
