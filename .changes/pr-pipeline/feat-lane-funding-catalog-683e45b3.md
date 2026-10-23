---
bump: minor
---

### Added

- [`.github/lane-funding.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/lane-funding.json),
  the catalog of the seven lane funding roles (`reviews`, `reviews-security`, `issue-lane`,
  `intake`, `pr-unblock`, `pr-verify`, `automations`): each role's target secrets, whether it is
  keyed, and each lane's workflow, job, launcher and the secrets its job reads today, with a JSON
  schema beside it. No workflow's secrets change. `callers.test.mjs` fails when a job that reads a
  Claude secret is missing from the catalog or reads other secrets than it lists, when a job reads
  an API key off `run-claude-cli`, or when a role's secret names do not follow its prefix.

### Changed

- The Funding section of the PR pipeline convention names the seven roles and points to the
  catalog instead of listing lanes in prose.
