---
bump: patch
---

### Changed

- `dependency-fix-refused` now routes `fail` with `needs-session` instead of `hold` with owner reason `security` and `needs-human`. A commit other than Dependabot's on a dependency update comes from one of our own actors, so the hold it raised guarded only against them. That makes it friction, not a security stop (owner direction, 2026-11-19: only a token or secret leak, an account compromise or billing goes to the owner). A session builder drops or rebuilds the commit, for example with `@dependabot recreate`, and the new head starts clean. #17344 waited for a person from 04:20Z until a session removed the label, though the recreate at 06:14Z had already removed the commit. `dependency-escalate-security` still holds a HIGH or CRITICAL risk in the update for the owner.
