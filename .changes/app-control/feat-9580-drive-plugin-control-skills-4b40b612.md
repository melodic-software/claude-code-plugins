---
bump: minor
---

### Added

- `/app-control:drive` now finds a control skill a plugin ships, named `<plugin>:control-<app>`, after looking for a project `control-<app>` skill. It loads the match, project or plugin, through the Skill tool and reads its `features/` from the base directory the tool reports. A project skill with the same `control-<app>` name wins, and the report names the skill used and where it came from.
