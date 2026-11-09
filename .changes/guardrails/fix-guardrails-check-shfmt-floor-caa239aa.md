---
bump: patch
---

### Fixed

- `/guardrails:setup check` now reports a `shfmt` row and fails it when the shfmt the Bash guards
  read commands through is missing or older than the floor in `prerequisites.json`, naming the
  version found, the floor and the upgrade. An older shfmt can read some commands differently and
  let them through.
