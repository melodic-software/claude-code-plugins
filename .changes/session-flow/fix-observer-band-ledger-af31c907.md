---
bump: minor
---

### Added

- `/observer` shows whether the observer's live checks are on and, for this session and the last 24 hours, its checks by trigger and outcome, tokens, latency, cold-cache checks and your answers. `/observer off` pauses live checks on this machine until `/observer on`.
- While a finding is shown, the next check clears it when the assistant has fixed it, and the ledger records it as resolved.
- Noted now marks the ledger entry confirmed, and each answer is recorded in the usage file.

### Changed

- The observer's band row: a blank line above it, the trigger that found the finding beside its category, the finding on one line with Why (`8`) showing the rule, evidence, this session's check cost and how to pause, and buttons ordered Send, Noted, Dispute, Why, Dismiss on hotkeys `5` to `9`, clear of the built-in side agent's `1` to `4` and `0`.
- A running-retro checkpoint no longer repeats a finding the observer already logged in the ledger.

### Fixed

- The observer appends to the running-retro ledger and its usage file instead of rewriting them, so a checkpoint written at the same moment is no longer lost.
