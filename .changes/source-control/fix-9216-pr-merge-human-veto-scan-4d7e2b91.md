---
bump: patch
---

### Fixed

- `babysit_merge.py --unattended --authority pr-merge` holds a pull request a person asked to hold before it enqueues: the autopilot tier's human-veto scan (issue comments, review summaries and inline review comments by a human that match `HUMAN_MERGE_VETO_RE`, blocking language or a blocking severity) now runs on the pr-merge path too, through one shared `human_blocking_logins`. The veto vocabulary is unchanged, so a bare "wait" holds nothing ([#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).
