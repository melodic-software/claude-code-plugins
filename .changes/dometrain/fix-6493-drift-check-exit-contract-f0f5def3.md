---
bump: minor
---

### Changed

- `/dometrain:sync`'s `scripts/update.sh` follows the shared drift-check exit-code contract: 0 no drift, 1 drift (including a missing baseline), 2 unverifiable (a missing tool, a failed fetch or write, or an unknown mode). Drift used to exit 2 and an unverifiable state 1. (#6493)
