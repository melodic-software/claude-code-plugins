---
bump: minor
---

### Changed

- `/context7:lookup update` follows the shared drift-check exit-code contract: 0 no drift, 1 drift (a CLI behind latest, changed upstream skill content, or a missing baseline), 2 unverifiable (a missing tool, an unreachable registry or upstream, a failed fix or refresh, or an unknown mode). Drift used to exit 0 and a missing tool 1. A `ctx7` that is not installed is reported but no longer counted as drift. (#6493)
