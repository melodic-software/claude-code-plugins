---
bump: minor
---

### Added

- `audit` allows one batched research pass in place of one call per finding when two or more findings qualify. Sources save under one packet directory, and each finding keeps its own `research:` record, graded unchanged by `collect-categories.sh`.
