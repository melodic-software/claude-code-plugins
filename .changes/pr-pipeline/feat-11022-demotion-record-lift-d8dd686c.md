---
bump: minor
---

### Changed

- `post-merge-demotion-alert.yml` writes a lift block into each canary and revert record it files: the lines `scripts/check-silent-revert.sh` attributes to a culprit in the pushed commits (its new opt-in `DELETED_SINK`), or the lines the revert commits deleted. A canary record `babysit_postmerge.py --remediate` filed first gets the block as a comment. The record bodies say they lift once that content is back on main or a referencing pull request merges with it.
- The `close-cleared` job checks out main and runs `babysit_lift.py close`, which comments on, unlabels and closes each lifted canary, revert or read-back record; it now also holds `pull-requests: read`. The pr-pipeline README states the lift rule and its one exception, a canary record with no lift block.
