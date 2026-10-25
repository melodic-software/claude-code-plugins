---
bump: patch
---

### Fixed

- The fix-ci dispatcher counts a head's earlier `pr-unblock / fix-ci` runs from the REST check-runs listing before it dispatches, instead of from the GraphQL check rollup, which lists only the newest run per check name. The per-head cap (`limits.limit-stops-per-head`) now stops a head that fix-ci-context skips each time, which was dispatched again after every base move. A head whose runs cannot be read is not dispatched (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
