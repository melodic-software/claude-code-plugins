---
bump: patch
---

### Changed

- Every job that calls the GitHub API with `GITHUB_TOKEN` and already checks out the repository logs the token's REST budget at its start and end through `.github/actions/log-api-budget`; `ci-status` gets a sparse checkout of that action for it. At the end each token gets one notice, `token=<name> workflow=<path> job=<id> run=<id> attempt=<n> limit= remaining= used= reset=<epoch> resource= cost=<N or na>`, so the jobs sharing a bucket can be told by its reset. The lanes App token is named `lanes-app` (was `lane`); the monitor-signals ceiling reads both names and both notice shapes.
