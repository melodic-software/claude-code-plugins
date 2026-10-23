---
bump: patch
---

### Fixed

- The hourly triage sweep re-dispatches intake for an issue whose intake run failed: the `needs-triage` floor label, which lands on open whether or not intake runs, no longer counts as triaged, so the missing intake comment decides. A filing records an in-progress state before it files, so a failed write cannot file twice (`.github/scripts/maintenance-audit-lane-runs/triage-sweep.mjs`, [#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).
- `status: needs-info` holds an issue like `status: needs-decision`: resolve-issue and apply-issue-patch start nothing on it, work-unblock neither adds `agent-ready` to it nor restarts it, and the WIP cap leaves it out of queued work. Pull request hold labels are unchanged ([#9216](https://github.com/melodic-software/claude-code-plugins/issues/9216)).
