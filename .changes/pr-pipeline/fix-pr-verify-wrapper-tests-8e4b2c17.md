---
bump: patch
---

### Fixed

- pr-verify no longer calls a Node test unrun when CI ran it through its sibling `.test.sh` in `test-bash`. A `.test.mjs`, `.test.js` or `.test.cjs` with such a wrapper runs only there, so `test-node` skips by design, and the verifier read that skip as the test never running. `upstream-jobs.json` now carries `wrapped_node_suites`: each Node suite in the judged head's tree that has a sibling `.test.sh`, with its wrapper, derived from the head's tree by the rule `scripts/plan-test-lanes.sh` applies. The prompt tells the verifier to judge those suites by the `test-bash` jobs.
