---
bump: minor
---

### Added

- **`/education:teach` remembers a closed mission.** Choosing close at the all-checks-met `resume` step writes a `Status: closed` line under the `MISSION.md` title. `list-workspaces.sh` marks that workspace `(closed)`, `status` shows it as closed, `explain` and `exercise` no longer treat it as active, and `resume` on it says the mission is closed and offers to reopen or revise it (deleting the line) or leave it closed, instead of offering close-or-revise again. New eval cases `resume-close-persists-status`, `status-closed-mission` and `resume-closed-mission` cover each behavior. ([#6408](https://github.com/melodic-software/claude-code-plugins/issues/6408))
