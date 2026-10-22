---
bump: minor
---

### Added

- intake-triage.yml writes the triage verdict as the lanes App after each triage run that applied: the proposed `work-class:` label, the Size, Complexity and Uncertainty issue fields, and `status: ready` or `status: needs-decision`, from the lane comment's class line and four verdict lines, each checked against a closed set (`.github/scripts/intake-triage/apply-verdict.mjs`, lane `intake-triage`, activity `apply-verdict`, effect `mutate-tracker`). It never adds `agent-ready`, keeps a class or field a listed human set, and drops the comment's "a maintainer confirms" wording once it applied the class ([#9213](https://github.com/melodic-software/claude-code-plugins/issues/9213)).

### Changed

- Intake triage follows a written priority, type and dimension rubric, and may no longer apply `good first issue` or `help wanted`.
