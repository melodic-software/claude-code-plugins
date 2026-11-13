---
bump: patch
---

### Added

- `behavior-probes`: a `hub-start` area of seven auto-mode cases, built by a new `cases/lib/hub-layout.sh` scaffold, checks what a session started in one repository may write in a sibling repository and its worktree under a stand-in `autoMode.environment`. Record 22 holds the live run: every action ran.

### Changed

- `behavior-probes`: `auto-mode/flag-automode-rule-denies` now takes its command from a file, with a new file-sourced control, because a prompt that names the exact command is the documented user-intent override of a soft block. Records 4 and 5 carry their reruns on Claude Code 2.1.323.
