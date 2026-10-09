---
bump: patch
---

### Added

- A `claude plugin eval` suite under `evals/` (#6651) with four cases: loading the saved login after `open`, asking the owner to re-save an expired login, never reading the saved login file, and the named-session snapshot-then-click-by-ref loop. Every grader is deterministic and every case grants only `Read`, `Glob`, `Grep` and `Skill`.
