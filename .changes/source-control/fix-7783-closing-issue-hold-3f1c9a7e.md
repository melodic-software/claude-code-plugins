---
bump: patch
---

### Fixed

- The pr-merge lane refuses a lane pull request whose linked issue carries a hold label, both at eligibility (`lane_eligibility`) and right before the enqueue (`recheck_lane_issue`), with `closing-issue-held:<label>` ([#7783](https://github.com/melodic-software/claude-code-plugins/issues/7783)). The hold set is `activities.resolve-issue.applies-when.labels-absent` in `docs/conventions/pr-pipeline.yaml`, read through the merge config reader (`PipelineConfig.issue_holds`, the union of the base's and the default branch head's), so the labels that keep an issue for a person are listed once. With no such list the tracker's human-gated role label holds instead. No resolved hold label (`closing-issue-holds-unresolved`) or an issue label set that cannot be read whole refuses. An edit to the issue after admission stays with the verifier's `verify:spec-changed`.
