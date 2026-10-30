---
bump: patch
---

### Changed

- **A red-main demotion record clears once main is green at a later commit.** The Demotion issue section now states that a `schedule` or `dispatch` record no non-human edited stops holding the rung once a newer attempt-1 green `pr-require-checks` run on main sits at a commit ahead of its SHA and on main's history; canary and read-back records stay human-close (#11262).
