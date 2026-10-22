---
bump: minor
---

### Added

- `/testing:check-visual-parity` captures each state through `/app-control:drive capture --kind screenshot` first when that skill is available, using drive's own launch as the one launch path and falling through to the Playwright CLI or the repository's harness when drive reports a capability gap or writes no PNG; the report names the route that captured each state.
