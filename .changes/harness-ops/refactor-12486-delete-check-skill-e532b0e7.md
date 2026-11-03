---
bump: major
---

### Removed

- `/harness-ops:check` is gone, with its probe file. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`, the command the hook notices already print. The `SessionStart` node notice now names `/harness-ops:prerequisites`.
