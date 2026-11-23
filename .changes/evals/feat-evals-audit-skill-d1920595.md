---
bump: minor
---

### Added

- `/evals:audit` reports an eval suite's health and edits nothing: skills with no case or no deterministic triggering case, judged graders with no labeled samples, legacy-only skills and missing should-not-fire cases, then judged findings on gate pairs, duplicates, grader fit and drift, each naming where its fix goes.
