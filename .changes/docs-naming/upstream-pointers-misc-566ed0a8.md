---
bump: patch
---

### Fixed

- `/docs-naming:generate-file-name-gate`, its emitted rule and checker templates, and the README no longer state when a path-scoped rule loads, a claim that had drifted from the live memory docs. They now give our own reason the gate is the deliverable (a rule only guides Claude in its session, blocks nothing, and never runs in CI), and the skill points at the live section with an as-of date and recheck trigger.
