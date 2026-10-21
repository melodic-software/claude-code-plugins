---
bump: patch
---

### Fixed

- `review-venue` no longer reads a lane as `local failing` because one pull request edited the lane's caller workflow: a run whose failed jobs all report `failure-class=skipped-validation` reaches no verdict, so the lane's health comes from the newest run before it. Any other failure, a usage-limit stop included, still reads failing ([review-venue.md](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/source-control/skills/pull-request/reference/review-venue.md)).
