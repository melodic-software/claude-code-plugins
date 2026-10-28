---
bump: patch
---

### Fixed

- The audit standards probes read a contract from `docs/contracts/<topic>/README.md` when it exists and fall back to the convention home, so a contract moved out of `docs/conventions/` is graded from its content, not the stub left at its old path.
