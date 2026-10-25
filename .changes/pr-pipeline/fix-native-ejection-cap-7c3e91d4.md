---
bump: patch
---

### Fixed

- `enable-auto-merge` no longer re-arms a lanes App pull request whose head the merge queue has removed for failed checks `merge.max-queue-ejections` times (default 2) since it last changed. GitHub does not re-arm a pull request the queue removes, and each scheduled run armed it again, so a head that kept failing its merge group was re-queued without end. The count and the limit are the gate's own, read through `babysit_verify_evidence.py evidence --lane-queue`. At the cap the pull request is left unarmed with the gate's `<!-- babysit-merge-queue-ejections -->` comment and no label, since a push resets the count; a count that cannot be read leaves it unarmed.
