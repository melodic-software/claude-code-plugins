---
bump: patch
---

### Fixed

- `review-dependency` no longer hands a pull request to a person when its verdict or context fails validation. `escalation-routes.json` routes `dependency-invalid` to a failing `pr-unblock/review-dependency` status with no label, and `apply-dependency-verdict.mjs` posts its verdict check as `lane-stopped`. `dependency-dispatch.mjs` then dispatches the same head again, through the `stopRelease` and `releasedBy` helpers `dispatch.mjs` uses, until `limits.limit-stops-per-head` such stops stand on it; at the cap it records the head and logs a warning. Every other `dependency-*` reason still holds for a person.
