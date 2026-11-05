---
bump: patch
---

### Changed

- **The `revert` demotion record is now filed by a new `file-revert` job whose token holds `issues: write` alone.** The alert job, which also holds `actions: write` and read scopes, still finds the revert and judges who enqueued the reverted pull request, then hands the record over through its job outputs; `file-revert` re-reads the revert records first so a revert commit is still filed once. Which reverts file a record is unchanged.
