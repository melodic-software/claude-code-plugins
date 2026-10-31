---
bump: patch
---

### Fixed

- pr-merge's `clear-escalations` sweep now also removes `needs-session` after a push that mends the stop. That holds when the head is no longer any stop's head, the newest `pr-unblock/*` status for each stop's activity at the new head, if any, is a success, and its checks pass, not counting `ci-status`, which the label keeps red. Before, only a same-head retry lifted the label, and a session had to remove it by hand after a new head. A `dependency-workflow-unpinned` stop still comes off only on its own head. If the cause still holds, the lane stops again on the new head and labels it again ([#11200](https://github.com/melodic-software/claude-code-plugins/issues/11200)).
