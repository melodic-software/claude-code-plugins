---
bump: minor
---

### Added

- The control-skill contract has a size budget: 16,000 characters for the hub and 4,000 for each feature file, counted the way `/skill-quality:check listing-budget` counts. `/app-control:map check` reports a file over its budget with the new `size-budget` rule, and `/app-control:map create` reports any it wrote as a warning that stops nothing.
