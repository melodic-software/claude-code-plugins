---
bump: patch
---

### Changed

- `pr-run-activity-write.yml` takes a required `role` input, the funding role whose OAuth token the
  caller passes, and the lane record names that role's token (`<ROLE>_CLAUDE_CODE_OAUTH_TOKEN`) as
  the run's credential instead of always `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN`.
  `work-resolve-issue` passes `issue-lane` and its own `ISSUE_LANE_CLAUDE_CODE_OAUTH_TOKEN`;
  `pr-refine` and `pr-unblock` pass `automations`.
