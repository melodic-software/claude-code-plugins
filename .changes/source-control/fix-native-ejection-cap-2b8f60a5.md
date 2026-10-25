---
bump: patch
---

### Fixed

- `/source-control:babysit-prs`: `babysit_verify_evidence.py evidence --lane-queue` (with `--lane-reviews` and `--base-sha`) adds a `queue` field to a line whose risk read holds nothing: the head's failed-check merge-queue removals since it last changed, the `merge.max-queue-ejections` limit, and at or over it the gate's refusal and its `<!-- babysit-merge-queue-ejections -->` comment body. A read that fails refuses as the gate's unreadable hold and names why in `readError`; a failed read of the failing runs keeps the refusal, with no comment and its error in `commentError`. The gate's unattended enqueue and this field share one function for the refusal and the comment body, `babysit_merge.queue_ejection_hold`.
