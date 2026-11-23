---
bump: minor
---

### Added

- The upstream changelog workflow checks the release's npm native build against `docs/upstream/claude-code-native-surfaces.min.json`. A changed passing summary opens a baseline-only draft in two jobs, `push-native-baseline-branch` and `publish-native-baseline-pr`, each with its own broker token. A person reviews, readies and merges the draft. The host fallback is changelog apply Phase 5 in the harness-ops plugin.
