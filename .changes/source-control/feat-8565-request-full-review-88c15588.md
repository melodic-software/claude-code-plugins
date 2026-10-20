---
bump: minor
---

### Added

- pr-merge requests a whole review of a lane pull request held only by findings an incremental review cannot clear: it records the request in the reasons comment, then converts the pull request to a draft and marks it ready, once per head and at most once per run, only while fewer than 35 jobs run and both tokens have 1,500 calls left ([README.md, Unattended merge](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/README.md)).
