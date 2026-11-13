---
bump: patch
---

### Changed

- `/source-control:pull-request`: the dispatching session owns a PR watch. A dispatched subagent stops once its PR is marked ready and reports the full head sha; the dispatching session watches and merges. The monitor reference, the monitor cadence default and the watch handoff say so, and the REST-polling note names one session watching several PRs instead of subagents each watching one ([#15792](https://github.com/melodic-software/claude-code-plugins/issues/15792)).
