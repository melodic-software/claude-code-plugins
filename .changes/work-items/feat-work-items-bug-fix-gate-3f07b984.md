---
bump: minor
---

### Added

- A seven-condition fix gate on `/work-items:work`'s bug path, under `bug_path.fix_gate` in `docs/conventions/work-items.yaml`, read from the default branch. `confirmed_repro`, `evidence_reviewed`, `no_fix_artifact`, `no_human_claim` and `root_cause_evidenced` are floors that stay on (a `false` is named and ignored); `before_after_runnable` defaults on; `budget_minutes` (90) and `scope` bound the fix. A failing condition stops the run with no fix and no PR, naming the condition.
