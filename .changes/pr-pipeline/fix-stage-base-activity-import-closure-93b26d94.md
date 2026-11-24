---
bump: patch
---

### Fixed

- `collect-base-activity` stages every file a script activity loads, transitively, at its repository path under `$RUNNER_TEMP/base-script`, and both activity runners run the script as `$RUNNER_TEMP/base-script/<script>`. `report-escalation.sh` now loads `pr-merge/refire-refused.mjs`, so its workflow-modified refusal hold fires, and sources the API budget wrapper; `declare-test-scope.mjs` loads and reads the base config, with resolve-config's rule files staged beside it; and `address-feedback.mjs`'s dynamic imports of `pr-verify/resolve-pr.mjs`, `intake-triage/admit.mjs` and `rate-guard.mjs` resolve. The write runner no longer hand-copies apply-patch's sibling modules.
