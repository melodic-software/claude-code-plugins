---
bump: major
---

### Changed

- **Breaking:** `/architecture:improve` now reads the `verification` level (`lib/read-verification.sh`, team file `<home>/architecture.yaml` at the default branch). At the default `light`, and at `off`, the deepening lens's Phase 1.5 and the conventions lens's "Verify before presenting" reproduce nothing: `confidence: strong` candidates, promotions to `Strong`, runtime claims and derived convention items reach the report labeled `unverified`, and the artifact's `phase-1.5` line is the skip token; the conventions lens proposes no `unverified` item for recording. Set `verification: standard` to restore the reproduction.
