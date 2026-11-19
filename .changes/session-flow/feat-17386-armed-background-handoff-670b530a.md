---
bump: minor
---

### Added

- arm a fresh background session for step-away before the person leaves

  step-away's fresh-session step launches through continue-in-background
  with the task file as the goal, takes the full session id that skill now
  reads from `claude agents --json --all`, and runs `away.py start` for that
  id from the attended session. The task file's header line names the away
  rules and the report path, since no hook gives them to the background
  session. A live probe of when the hooks first see the
  state is recorded in goal-probe.md.

### Fixed

- `away.py refresh` finds a session's transcript by its id when no hook
  recorded the path, so a background session armed from another session
  still lists its external actions
