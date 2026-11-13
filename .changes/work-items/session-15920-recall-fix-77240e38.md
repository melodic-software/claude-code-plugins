---
bump: minor
---

### Added

- `/work-items:track view --history` and the seam's `get-item <id> --history` report when an item
  was closed and reopened: `state_history` with its `closed` and `reopened` events and a
  `reopen_count`. The GitHub adapter reads them from the issue timeline over REST, one paginated
  read made only when asked for. An adapter whose manifest declares no `features.state_history`
  (local-markdown and the jira, gitea and linear seeds) gets `available: false` with a reason, so
  a caller can tell "cannot know" from "never reopened".
