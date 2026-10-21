---
bump: patch
---

### Fixed

- An `agent-ready` issue the issue lane skips on its dimensions (`split-required`, `research-first`, `probe-first`, `not-assessed`) no longer ends the run green and silent: work-resolve-issue.yml's `report-skip` job runs `report-outcome` with the new `dimension-skip` input, which labels the issue `needs-human`, removes `agent-ready`, and comments the next step (`/work-items:decompose`, research, a probe, or setting the fields) with no model run ([pr-run-activity.md, Issue mode](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#issue-mode)).
