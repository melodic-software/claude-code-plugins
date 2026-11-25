---
bump: minor
---

### Added

- `/observer` shows whether the observer's live checks are on and, for this session and the last 24 hours, its checks by trigger and outcome, tokens, latency, cold-cache checks and your answers. `/observer off` pauses live checks on this machine until `/observer on`.
- While a finding is shown, the next check clears it when the assistant has fixed it, and the ledger records it as resolved.
- Noted now marks the ledger entry confirmed, and each answer is recorded in the usage file.
- After Dismiss, the band offers the built-in side agent's answers once (`5` That was helpful, `6` Not relevant, `7` Couldn't understand, `8` Turn off checks for this session, `9` Close) and clears itself after 20 seconds. Not relevant keeps the next checks from reporting that finding or ones like it; Couldn't understand makes later checks write in plainer words.
- Session start deletes observer files (usage files and the catch-up's working files) not written for 30 days.

### Changed

- The observer's band row: modeled on the built-in side agent's, a `◆` mark and a blank line above and below it, the trigger that found the finding beside its category, the finding on one line with Why (`8`) showing the rule, evidence, this session's check cost and how to pause, and buttons ordered Send, Noted, Dispute, Why, Dismiss on hotkeys `5` to `9`, clear of the built-in side agent's `1` to `4` and `0`.
- A running-retro checkpoint no longer repeats a finding the observer already logged in the ledger.

### Fixed

- The observer appends to the running-retro ledger and its usage file instead of rewriting them, so a checkpoint written at the same moment is no longer lost.
- The running-retro ledger now lives in the repository's main checkout, so findings from a session started in a linked worktree survive the worktree's removal.
- Where `$.process.run` is unavailable, ledger and usage writes fall back to a checked read and rewrite instead of being lost.
