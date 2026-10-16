---
bump: minor
---

### Added

- `/testing:audit --judge [<base>]`: an opt-in pass that hands each test block the change added or changed to the new `testing:test-judge` agent (Read, Grep and Glob only) on another model class, which reports FLAG, PASS or UNKNOWN for where its expected value came from, with checked quotes and a proposed diff it never applies. `--persist-findings` also writes its verdicts for `/testing:cleanup`.

### Changed

- `/testing:setup check`'s hook-entry section points at `/testing:audit` and names the globs the `test-weaken` hook skips, in place of printing a per-edit `PostToolUse` settings entry.

### Removed

- The per-edit `test-scan` hook rows (the `PostToolUse` Write/Edit rows and the Bash row) and the task-end test judge hooks (the background `PostToolUse` job, the `Stop` relay and the `SessionStart` catch-up). Can't-fail findings come from `/testing:audit` on demand; `test-weaken` stays.
- The `test_judge_enabled`, `test_judge_model`, `test_judge_fallback_model`, `test_judge_effort` and `test_judge_session_runs` options.
