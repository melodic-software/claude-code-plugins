---
bump: patch
---

### Added

- Sixteen outcome eval cases under `evals/` for `explore-directions`, `pressure-test` and `build-generator`.
- `explore-directions` and `build-generator` accept a leading `--` that ends the actions, so a scope
  or subject can start with an action word (`/prototype:explore-directions -- controls page`).
