---
bump: patch
---

### Changed

- `babysit-prs` merge gate: in the pr-merge lane, reads that are the same for every candidate are shared by the run's gate processes through the file `BABYSIT_RUN_CACHE` names, instead of being repeated per candidate. The acting login and a credential pass are reused only under the same credentials; a credential refusal is read again. A collaborator permission and the trusted-actor list are reused for two minutes, and a failed read is never shared. A run head found on main is shared for the run; one not found is compared again. The merge-queue sweep skips a queued entry another candidate judged and kept only while the reads behind that judgment, its verdict listing included, began at most two minutes ago; a gate always judges its own entry, and a held entry or a failed dequeue keeps nothing. The verdict reader's compares of a run head to main now use the job's `GITHUB_TOKEN`, off the lane App's quota. Without the variable nothing changes.
