---
bump: minor
---

### Added

- `/work-items:work --issue <n> --ci`: the mode the `work-resolve-issue` CI lane runs on one issue
  labeled `agent-ready`. It reads the issue the runner wrote, pushes back on an unclear issue,
  otherwise commits the change, and writes `work-outcome.json` (`done`, `pushback` or `stopped`)
  for the lane to open a draft PR or hand the issue back.
