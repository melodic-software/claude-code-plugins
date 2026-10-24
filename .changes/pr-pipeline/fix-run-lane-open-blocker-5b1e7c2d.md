---
bump: patch
---

### Fixed

- The issue lane no longer runs an agent-ready issue that has an open `blocked_by` issue or pull request (owner decision Q95). The admit job lists the blockers after the trusted-trigger check. An open blocker, or a list it cannot read, skips the run with a notice or warning: no model turn, no `needs-human`, and `agent-ready` stays on. work-unblock's sweep no longer re-fires, strands or hands to a person an agent-ready issue with an open blocker. It re-fires a run the blocker gate skipped once no blocker is open (`.github/workflows/work-resolve-issue.yml`, `.github/scripts/work-resolve-issue/check-blockers.mjs`, `.github/scripts/work-unblock/label-unblocked.mjs`).
