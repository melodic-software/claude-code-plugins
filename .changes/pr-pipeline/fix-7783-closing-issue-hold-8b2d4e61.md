---
bump: patch
---

### Changed

- The pr-merge lane's eligibility section documents the linked-issue hold ([#7783](https://github.com/melodic-software/claude-code-plugins/issues/7783)): at eligibility and again before the enqueue, a linked issue carrying a label from `activities.resolve-issue.applies-when.labels-absent` refuses with `closing-issue-held:<label>`, the tracker's human-gated role label holds when that list is absent, and an unreadable label set refuses. An edit to the issue after admission is the verifier's `verify:spec-changed`.
