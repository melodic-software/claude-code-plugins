---
bump: major
---

### Removed

- `/context-guard:check` is gone, with its probe file. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`, the command the hook notices already print. The mods probe moved to `scripts/check-mod-load.sh`, which reports the mods floor and how to read this session's state.
