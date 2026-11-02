---
bump: minor
---

### Changed

- `post-merge-demotion-alert.yml` files demotion, revert and post-merge-failure records with no `needs-human` label, then locks each and dispatches intake triage for it, as it does its fix issues, so a lane picks it up; each quarantine issue the suite judge files goes the same way, and an issue not sent fails the job. A schedule or dispatch record still clears once main is green at a later commit; canary, revert and read-back records clear only on a person's direct close.
- red-main's report plans a failed-guard revert as a pull request opened ready for review and labeled `auto-revert` only, for the review lanes and the merge lane, instead of a `needs-human` draft. The guards are unchanged.
