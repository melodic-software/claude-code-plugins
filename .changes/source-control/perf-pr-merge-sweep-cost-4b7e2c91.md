---
bump: minor
---

### Added

- `merge.max-queue-ejections` (default 2, 1 to 20): the unattended merge gate no longer enqueues a head the merge queue has removed that many times for failed checks since the head last changed (a pushed commit or a force push). The merge-queue read takes the pull request's last 20 removal, commit and force-push timeline items; the refusal names the head, a push resets the count, and an unreadable timeline (or 20 items with no head change among them) refuses the enqueue. A refused head gets one `<!-- babysit-merge-queue-ejections -->` comment, upserted like the verifier escalation's, linking the failing `merge_group` runs.

### Changed

- In the pr-merge lane the gate reads the verifier verdict before the review evidence and the changed files. A verifier refusal now skips both, reports the `verify:` reason instead of `risk:<score>`, still dequeues the pull request's own entry, and leaves the risk comment to the first run the verifier passes.
- A pr-merge run shares a FAIL verdict's run record across its gate processes for the whole run instead of two minutes: the record's origin rests only on fields a re-run keeps, and the branch check stays live.
