---
bump: patch
---

### Changed

- The confirm and measure `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Thirty new cases: for confirm, the refactor criterion for a large reshape (`confirm-refactor-large-reshape-equivalence`), routing (`confirm-build-question-no-trigger`, `confirm-faster-claim-redirects-to-measure`), live-app delegation (`confirm-new-endpoint-runs-e2e`, `confirm-live-app-run-fallback`), observation doubt (`confirm-stale-observation-ruled-out`), proof-level resolution and proof boxes (`confirm-proof-level-*` and `confirm-strict-*` cases), live workers (`confirm-live-workers-*`, `confirm-cloud-host-unverified-line`), the run-e2e decision without app-control (`confirm-app-control-absent-e2e-decision`), the missing-entry-point hold, load-bearing assumptions, journey preconditions, stand-in caveats, lessons and the evidence loop; for measure, the no-baseline compare for both families and the route to confirm. `confirm-intent-from-plan-brief` gains the outcome-report, intent-match-table, couplings-table and verdict-word graders, and `confirm-prep-light-mechanical-blocks` the failing-assertion, no-stage-2 and stops-before-outcome graders.
