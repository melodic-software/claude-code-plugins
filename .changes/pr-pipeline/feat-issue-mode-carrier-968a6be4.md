---
bump: minor
---

### Changed

- An issue run of the read runner (`work-resolve-issue`'s `resolve-issue`) now hands its reply, run fields, patch and outcome files to the scan job only sealed to the scan-carrier key, as a PR-mode run does. The scan job opens them, scans them for credentials, and is the only job that uploads them; the run job uploads nothing, and its step summary shows no model text but a gate skill's verdict. See [The scan job](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#the-scan-job).
- The read runner's patch outputs now come from the scan job alone. Its issue outputs (`scan-issue-run-started`, `scan-reuse-branch`, `scan-resume-branch`, `scan-resume-tip`, `scan-base-sha`) come from a new `issue-fields` job, which runs whatever the run job's result, holds each run job field to its closed set and combinations, and re-derives any branch claim with the default-tip earlier-work check. `work-resolve-issue.yml` reads only these, and the reuse summary job takes its code from the default branch tip. The run-job-sourced `issue-run-started`, `reuse-branch`, `resume-branch`, `resume-tip` and `base-sha` outputs are removed.
- The skill's `work-outcome.json` is cut at 48 KiB, down from 64 KiB, so every sealed payload at its cap still fits the five chunks a job's outputs hold.
