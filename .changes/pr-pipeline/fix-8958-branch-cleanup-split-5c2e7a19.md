---
bump: patch
---

### Changed

- maintenance-delete-stale-branches runs as two jobs. A plan job whose token writes nothing reads the branches, issues and pull requests and hands at most `max-deletes-per-run` candidates to a delete job as an artifact. The delete job alone holds `contents: write`, reads no issue or pull request text, and refuses a list for another repository, over the cap, or with an entry outside the rule's shape. No permission is added.
- The delete is one GraphQL `updateRefs` per branch with `beforeOid` set to the listed tip, in place of `DELETE git/refs/heads/<branch>`, so a push that lands after the delete-time re-read makes GitHub refuse the delete and the branch is reported as skipped.
