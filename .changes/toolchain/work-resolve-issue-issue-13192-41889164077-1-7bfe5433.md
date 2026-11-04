---
bump: patch
---

### Changed

- The resolution-ladder reference, the `check` and `setup` skills and the setup evals now call
  `.claude/ecosystems/<ecosystem>.local.yaml` the personal override, the marketplace's name for
  the config cascade's gitignored layer (#13192). Behavior is unchanged.
