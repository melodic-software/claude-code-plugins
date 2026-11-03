---
bump: major
---

### Removed

- `/guardrails:check` is gone. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`, the command the hook notices already print. With `jq` missing the guards deny that Bash call too, and the denial names `jq`; `/guardrails:setup check` still reports it from its load-time rows.
