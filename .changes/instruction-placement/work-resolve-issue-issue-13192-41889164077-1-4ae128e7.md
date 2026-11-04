---
bump: patch
---

### Changed

- The consumer-config reference, the `realign` skill and the `delta` and `realign` evals now call
  the config cascade's gitignored `instruction-placement.local.md` layer the personal override,
  the marketplace's name for it (#13192). Behavior is unchanged.
