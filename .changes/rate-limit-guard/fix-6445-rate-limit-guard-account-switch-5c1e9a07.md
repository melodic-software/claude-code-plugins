---
bump: patch
---

### Fixed

- After an account switch the module no longer restates or sends the old account's windows. It keys the signed-in account on `.oauthAccount.accountUuid` in `.claude.json` (the email when no UUID is there), and when that changes, or a window's reset time reads more than a minute earlier than the recorded one, it drops the latched levels, pending lines, handed-off suggestions and queued toasts. When a window was past quiet or a line was still due, it sends Claude one line saying earlier lines no longer apply, with the current reading or that the new account has none yet.

### Changed

- A restatement after a compaction, a resume, `/clear` or a reload states the current reading rather than the one that crossed into the level, and is not made while the reading is below that level.
