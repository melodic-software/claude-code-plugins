---
bump: minor
---

### Added

- `/testing:run-e2e` resolves a feature id named in the scenario, either `<module>/<feature>` or a single-level `<feature>`, to its feature file in `/app-control:drive`'s order, on the drive route and on its own driving alike. The id comes from the control skill's index path, and a legacy flat `features/<feature>.md` gives `<feature>`, so the touched-feature refresh names `/app-control:map refresh cart`, never `cart.md`.
