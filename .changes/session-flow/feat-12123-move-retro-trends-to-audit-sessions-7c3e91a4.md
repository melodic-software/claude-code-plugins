---
bump: major
---

### Changed

- **`/session-flow:retro trends` is now `/session-flow:audit-sessions trends`.** Retro no longer has a `trends` mode: asked for one, or for scores across sessions, it names `/session-flow:audit-sessions trends` and stops without analyzing a session. The new action runs the same process, the score history analysis and the delivery metrics from `/work-items:measure-delivery`, and reads the same score history file, which retro's session and quick modes still write. Update anything that still runs `/session-flow:retro trends`: saved prompts (routines, scheduled tasks, `/loop`) and `Skill(...)` permission rules.
