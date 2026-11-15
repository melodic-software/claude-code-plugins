---
bump: minor
---

### Added

- **`/playbooks:skill-authoring`, skill criteria, Body.** A rule for a skill that needs a behavior
  another skill owns: call that skill by name and write only your own steps around the call; its
  instructions, checklist and defaults stay out of the body, because a copy goes on being
  followed after the owner changes.
