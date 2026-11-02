---
bump: patch
---

### Changed

- The main-run review (`pr-review-main.yml`) no longer reviews a head again when both lanes already have a verdict the merge gate binds there: pr-require-checks completes several times on one head, and each completion started both model reviews. The trigger job reads each lane's verdict artifacts, their runs and the head's record check runs, and decides with the gate's own predicate, counting a verdict only when its run's main commit has main's current review criteria (`criteria.txt`, which the copy steps also read); a verdict judged under other criteria, a failed or cancelled review, another head of the same tree, or any failed read reviews again. No review leg or record job starts for a pull request that changes no lane source, or for a head already reviewed.
