---
bump: patch
---

### Changed

- The rate guard keeps a rate-limit reading of every guarded call under `API_BUDGET_TOKEN`, so every Node script's calls reach the job-end api-budget notice, not only `budgetedFetch`'s. The log-api-budget action adds an `api-calls <token>=N not-modified=M` line: this job's own calls, which the notice's `cost` (a counter every concurrent job shares) is not. The jobs that posted no notice now post one: intake-triage's born-triaged and refine-select, pr-verify's two judge jobs, pr-unblock's four select and context jobs, post-merge-demotion-alert's report-red-main, and the audit-lane-runs, delete-stale-branches, monitor-signals and reconcile-lost-runs jobs. No call is added.
- pr-feedback-dispatch's rerun-ci-status sends each repeat poll of the pr-require-checks run as a conditional GET on the last answer's ETag; a 304 stands for that answer, so the poll keeps its 60 s pace, its 10-minute cap and its decisions. Each 304's reading reaches the job's notice, which shows whether GitHub counts a 304 against `GITHUB_TOKEN`.
- pr-merge's dispatch-full-run sends each read of the full run after the first as a conditional GET on the last ETag; a 304 means the run is still going, so the wait keeps its three-minute reads, its 39-minute ceiling and its red-run dispatch.
