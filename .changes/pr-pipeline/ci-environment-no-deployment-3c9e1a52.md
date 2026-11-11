---
bump: patch
---

### Changed

- The scan jobs that hold the scan-carrier key (pr-run-activity-read.yml, upstream-apply-changelog.yml, maintenance-tidy-code-upkeep.yml) name their environment as `{ name: pr-pipeline-scan-carrier, deployment: false }`: the job still gets the environment's secret under its main-only branch policy, and GitHub records no deployment. `scripts/check-read-caller-keys.sh` now accepts only that exact form on the read workflow's `scan` job.
