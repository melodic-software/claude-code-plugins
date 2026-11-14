---
bump: minor
---

### Added

- `stills.py --scan-pattern <regex>` (repeatable) adds a pattern the storyboard scan refuses, on top of its floor; a pattern that does not compile fails the scan (exit 4). The produce skill passes the caller's patterns to the renderer and the narration.
