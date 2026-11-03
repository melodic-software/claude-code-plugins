---
bump: major
---

### Removed

- The `check` skill is gone. To check this plugin's prerequisites, run `node "<plugin root>/lib/prerequisites.mjs" check "<plugin root>"`. `/disk-hygiene:setup check` also covers the launcher registration and the interpreter ladder. `prerequisites.json` now declares Python, and the guard messages name the checker.
