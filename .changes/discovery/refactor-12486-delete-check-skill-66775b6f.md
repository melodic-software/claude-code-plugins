---
bump: major
---

### Removed

- `/discovery:check` is gone, with its probe file. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`, the command the hook notices already print. The hook registration probe moved to `scripts/check-hook-registration.sh`, which runs after the checker.
