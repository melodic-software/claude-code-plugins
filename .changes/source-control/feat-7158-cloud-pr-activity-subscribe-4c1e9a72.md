---
bump: minor
---

### Changed

- **`pull-request` monitor and `babysit-prs` subscribe to PR activity in cloud sessions** ([#7158](https://github.com/melodic-software/claude-code-plugins/issues/7158)). When the session offers `mcp__claude-code-remote__subscribe_pr_activity`, the monitor calls it for the PR after it arms the 60-90s poll, runs one iteration on each event wake, and unsubscribes at self-termination. `babysit-prs` subscribes once per PR per session, rescans the PR an event names, and unsubscribes when the PR is merged or closed. The poll stays at its cadence and remains the source of truth: in a cloud session probe, reviews and failed checks produced events, but the push and the successful and skipped checks did not. A session without the tool, or whose subscribe call fails, polls alone.
