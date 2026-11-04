---
bump: patch
---

### Changed

- The `codify` skill, the findings-buffer contract, both schemas and the settings scripts'
  comments and test labels now call the config cascade's gitignored `*.local.yaml` layer the
  personal override, the marketplace's name for it (#13192). Behavior is unchanged.
