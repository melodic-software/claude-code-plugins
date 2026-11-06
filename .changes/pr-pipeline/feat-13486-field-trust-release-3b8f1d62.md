---
bump: minor
---

### Added

- `models.issue-status.bot-setters`: the bot accounts whose Work status value counts for every state but agent-ready, here github-actions[bot] and the melodic- Apps of `trusted-actors.json`. The config reader rejects a third-party bot, the lanes App and a repeated id (`undefined-status`); a melodic- entry `trusted-actors.json` no longer lists as that bot stops counting, so its value reads as unset. agent-ready still counts only from a listed human or the lanes App.
- `intake-reenter` starts on `issues: field_added` and `field_removed` for the Work status field from a person. When a listed human moves a hold that exists only on the field to none or needs-triage, on an issue with no status label but `needs-triage`, it adds `needs-triage`, sets the field to needs-triage when the release left it empty, and dispatches intake once.
- resolve-config's `fieldEvents` reads each Work status field event's actor, time and values; `write-status.mjs`'s `statusWriter` sets a named state and throws `StatusWriteError` when the write does not land.
