---
bump: minor
---

### Added

- `/mutation-testing:audit --persist-findings` writes each demonstrated equivalent mutant, with its
  demonstration, to a `## Declined candidates` section of the findings file, which the fix action
  does not parse. The suppression record still never holds an equivalent mutant.
