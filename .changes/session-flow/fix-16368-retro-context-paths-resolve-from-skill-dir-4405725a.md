---
bump: patch
---

### Fixed

- `/session-flow:retro`: every mention of its mode files links `context/session.md` and
  `context/quick.md` relative to the skill's own folder, and "Spoke paths" says those files sit
  beside the skill's SKILL.md, so a run no longer looks for them under the plugin root.
