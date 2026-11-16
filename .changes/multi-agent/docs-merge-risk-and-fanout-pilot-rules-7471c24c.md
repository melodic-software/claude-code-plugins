---
bump: minor
---

### Added

- The fan-out guard section now asks for one pilot worker and a check that plan usage remains before a fan-out wider than about four workers, since a usage limit reached mid-fan-out stops every worker at once.
