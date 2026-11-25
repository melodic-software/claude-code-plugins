---
bump: major
---

### Added

- The session observer is now a hooks module plus a catch-up. With `observer_enabled` on, a live check runs on every 6th model step of a long turn: a no-tools fork of the main conversation that reports at most one process fault tied to a written rule or owner decision. A finding goes to this session's running-retro ledger and to one row above the prompt (`1` Send to Claude, `2` Noted, `3` Dispute, `0` Dismiss); nothing reaches the conversation unless sent. Repeats across sessions and disputed findings are suppressed, ignored findings back off, and each check's token usage is recorded in a per-session file under the plugin data folder.
- `observer_step_check` (default on) and `observer_turn_end_check` (default off until its cost is measured) choose the live triggers.
- At each interactive session start, a SessionStart hook analyzes up to two ended sessions that got no live checks, such as headless lanes, with the existing headless analysis.
- The plugin now declares `engines["claude-code"]` `>=2.1.331`.

### Removed

- The detached transcript tailer that polled each session for up to 24 hours, with `observer_poll_seconds` and `observer_max_seconds`. `observer_idle_seconds` now sets how long a transcript must be unchanged before the catch-up treats its session as ended.
- The `/session-flow:running-retro arm` action: the observer needs no arming.
