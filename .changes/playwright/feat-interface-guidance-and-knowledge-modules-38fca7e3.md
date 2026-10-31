---
bump: minor
---

### Added

- `/playwright:playwright` gains an animation capture recipe: install the page clock before navigation and step it for script-driven motion, hold page-load entrances with an init script, seek each of the target's declarative animations from its own start and resume them afterward, report each animation's target, property, values, timing and progress, and measure long frames in a separate full-speed pass with no clock. A local page is served from `127.0.0.1` on a free port instead of a `file:` URL.
