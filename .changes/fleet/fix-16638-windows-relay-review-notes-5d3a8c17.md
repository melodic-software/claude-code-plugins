---
bump: patch
---

### Fixed

- The reach skill's Windows-lane profile start removes the prompt file on every path its script exits by, stops with "not started" when launch prints no `claude` command or `claude.exe` does not start, and refuses a background prompt that begins with `-`, which `claude.exe` would read as an option.
