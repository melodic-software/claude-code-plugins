---
bump: patch
---

### Fixed

- `babysit_merge.py --unattended --authority pr-merge` holds a pull request before it enqueues when an owner, member or collaborator's newest comment (issue comment, review summary or inline review comment) says "do not merge" (`HUMAN_MERGE_VETO_RE`). A later comment from that person lifts the hold. The autopilot tier's comment reading moves into one shared reader, and the tier's own wider scan is unchanged. A bare "wait", or a blocking word such as "regression", holds nothing on the lane ([#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).
