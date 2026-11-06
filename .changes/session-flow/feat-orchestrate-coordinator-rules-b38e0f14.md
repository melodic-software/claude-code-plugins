---
bump: minor
---

### Added

- `/session-flow:orchestrate coordinator` loads four rules from `context/coordinator.md`: standing orders as numbered lines restated on every spawn and resume; each human approval parked as an item with its decision, recommendation and what happens if unanswered; a loop tick that checks workers by what they did and stays quiet when nothing changed; and one writer per shared surface, with a per-tick environment-improvement note to the corrections buffer when that plugin is enabled. One eval case covers a quiet tick and a parked gate.
