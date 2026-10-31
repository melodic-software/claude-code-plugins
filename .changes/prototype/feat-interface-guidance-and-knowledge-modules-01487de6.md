---
bump: minor
---

### Added

- `/prototype:build-generator`, a user-invoked skill for an artifact prompting keeps missing: it diagnoses why the direct path fails, pitches the tool that closes that gap, builds a throwaway generator with live controls and a save button that writes the configuration to a project file, then harvests the saved output into the real artifact and deletes the tool. Arguments `save-output`, `add-controls` and `export <format>`; `/playgrounds:use` is offered for the dial-in case when it is available.
- `context/control-panel.md`, the shared rules for a prototype's control panel: what goes on it, controls writing CSS variables, visible and copyable values, placement and replay.
- `context/discipline.md` gains the exception that lets `build-generator`'s tool and saved configuration live in the project while the person tunes, with the tool deleted after harvest.
