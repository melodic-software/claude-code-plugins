---
bump: patch
---

### Changed

- The config reference and the `setup` skill now call the config cascade's gitignored `*.local.*`
  layer the personal override, the marketplace's name for it, and an `audit-noise` test fixture
  uses the same words (#13192). Behavior is unchanged.
