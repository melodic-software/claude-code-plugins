---
bump: minor
---

### Changed

- **Claude can now load `/disk-hygiene:clean` through the Skill tool.** The skill sets `disable-model-invocation: false`, so a request such as "clean up my /tmp" reaches it without a typed slash command. Loading it removes nothing. The confirmation gate, preview token, kill switch and guard are unchanged, and every removal still needs the user's own answer naming one tier and its paths. When Claude loads the skill, an `--execute` it passes counts as an execution request only when a user message asked for removal. A new eval checks that a model-invoked run stops at the gate. A session where Claude loaded `clean` this way gets no resume notice, because that notice keys on a marker that only the typed command writes.
