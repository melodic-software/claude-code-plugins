---
bump: patch
---

### Changed

- `setup`, the `audit` procedures and the `audit-pass` suppression reference now call the config
  cascade's gitignored `*.local.*` layer the personal override, the marketplace's name for it
  (#13192). Behavior is unchanged.
