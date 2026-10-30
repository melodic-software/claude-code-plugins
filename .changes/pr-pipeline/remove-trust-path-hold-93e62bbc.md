---
bump: patch
---

### Removed

- ci-workflows' `pr-require-checks-trust-paths` hold no longer runs here, by owner direction (trust-path holds come off): its caller workflow and its JSON config are gone, and `scripts/sync-hold-floor.py` no longer writes the config. `merge.trust-path-hold-apps` still feeds ci-status's inline hold.
