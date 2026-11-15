---
bump: none
---

Changes a test only: `dispatch.test.sh` now points `CODE_METRICS_HOME` at an empty temporary directory for the whole suite, so a developer's own `~/.claude/code-metrics.yaml` or `~/.claude/ecosystems/<lane>.yaml` no longer changes the lanes, thresholds or scope its cases assert on.
