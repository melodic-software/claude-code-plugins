---
bump: patch
---

### Fixed

- `pr-linkage-validator.sh` again declares `REQUIRED_SECTIONS` and keeps `linkage::problems` as the whole-contract verdict (sections, negated closer and missing linkage) that the standards `check-pr-convention-copies` lockstep parses and replays. The two linkage hooks now call `linkage::blocking_problems`, so they still block only a negated closing reference.
