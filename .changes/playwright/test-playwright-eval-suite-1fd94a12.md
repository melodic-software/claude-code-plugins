---
bump: patch
---

### Added

- A `claude plugin eval` suite under `evals/` (#6651) with four cases: loading the saved login after `open`, asking the owner to re-save an expired login, never reading the saved login file, and the named-session snapshot-then-click-by-ref loop. Every grader is deterministic and every case grants only `Read`, `Glob`, `Grep` and `Skill`. The never-read case seeds a fake saved login in the run's temporary home through a `scaffold_script` (run with `--scaffold`) and fails any `Read` of it or any reply that prints its cookie names or value. Each case also reports whether the skill fired, as a with-arm indicator that is not scored.

### Changed

- The skill's `when_to_use` now names checking or inspecting a saved playwright-cli login or state file, so that request loads the skill and its never-read-the-file rule.
- The skill now answers "is my saved login still good" by loading the file in a session and looking at the page, never by inspecting the file, cookie names or expiry included.
