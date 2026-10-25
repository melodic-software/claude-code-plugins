---
bump: patch
---

### Fixed

- The fix-ci dispatcher counts a head's earlier `pr-unblock / fix-ci` runs from the REST check-runs listing before it dispatches, instead of from the GraphQL check rollup, which lists only the newest run per check name. The per-head cap (`limits.limit-stops-per-head`) now stops a head that fix-ci-context skips each time, which was dispatched again after every base move. A head whose runs cannot be read is not dispatched (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`).
- A head that reaches the per-head cap in fix-ci or resolve-conflicts now gets one `::warning::` annotation on the dispatcher run that finds the cap, naming the PR, the head and the run count. The head then goes into the dispatch record, so later dispatcher runs skip it without reading its hold, check runs or required run (`.github/scripts/pr-unblock/fix-ci-dispatch.mjs`, `.github/scripts/pr-unblock/dispatch.mjs`, `.github/scripts/pr-unblock/limit-stop.mjs`).
