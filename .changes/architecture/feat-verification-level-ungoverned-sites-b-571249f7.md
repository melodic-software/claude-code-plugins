---
bump: major
---

### Changed

- **Breaking:** `/architecture:improve` now reads the `verification` level (`lib/read-verification.sh`, team file `<home>/architecture.yaml` at the default branch). At the default `light`, and at `off`, the deepening lens's Phase 1.5 reproduces nothing: `confidence: strong` candidates, promotions to `Strong` and runtime claims reach the report labeled `unverified`, and the artifact's `phase-1.5` line is the skip token. The conventions lens still reproduces every derived item. Set `verification: standard` to restore the reproduction.
