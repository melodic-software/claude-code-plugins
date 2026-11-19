---
bump: minor
---

### Added

- hand off a fresh session already armed for step-away

  continue-in-background takes --step-away "<words>": the launch payload's
  first line becomes /session-flow:step-away <words>, so the background
  session arms its own absence under its own id and its Stop hook holds the
  completion condition. step-away's fresh-session step now hands off armed
  through it instead of unarmed. A live --bg probe is recorded in
  goal-probe.md.
