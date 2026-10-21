---
bump: patch
---

### Fixed

- babysit-prs never updates the branch of a pull request carrying the tracker's standards-sync role label (`standards-sync` unless `.work-item-tracker.json` `config.role_labels` maps it): `refresh_pr_branch.py` refuses it, and the unattended enqueue skips its update from the base, reporting `checkInputs.updateSkipped`, then enqueues as after a refused update. The sync App is that branch's only writer, and a merge commit from the base fails its managed-files guard. An unreadable label refuses the refresh and holds the enqueue, since a stale head would fail the queue's merge.
