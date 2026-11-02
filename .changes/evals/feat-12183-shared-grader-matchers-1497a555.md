---
bump: minor
---

### Added

- Shared grader matchers: `matchers/fragments.json` holds tested sub-patterns for command position, token argument and table verdict cell, and a case builds a `regex` or `tool_used` grader from them in `<case>/matchers.json`. `skills/validate/scripts/check-matchers.py` grades every fragment's and every built grader's samples under Python's `re` and node's `RegExp`, requires samples for each built grader, and fails when `case.yaml` drifts from the build (`--write` rewrites it). Its suite runs over every plugin's evals in CI.

### Changed

- `/evals:validate` now grades `tool_used` `input_match` samples under JavaScript too, not only `regex` graders.
