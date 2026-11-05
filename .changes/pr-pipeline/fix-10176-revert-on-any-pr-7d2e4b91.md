---
bump: minor
---

### Changed

- **A push to main that reverts any merged pull request now files the `revert` demotion record**, whoever put that pull request in the merge queue; before, a revert of one a person queued filed nothing. The record is now filed by a new `file-revert` job whose token holds `issues: write` alone; the alert job, which also holds `actions: write` and read scopes, finds the revert and hands the record over through its job outputs, and `file-revert` re-reads the revert records first so a revert commit is still filed once.
