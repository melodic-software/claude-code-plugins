---
bump: patch
---

### Fixed

- `work-resolve-issue` no longer writes `Hold: a human merges this` on a reuse PR only because the runner's checks or its leak scan did not report (missing, for another tip, `failed` or no word). That line also failed `ci-status`, so pr-verify never ran and the PR waited on a person for a check CI runs anyway. The merge still needs `ci-status`, which needs `lint-repo` and its gitleaks scan, both fail-closed on any non-success. A failed runner check, a leak scan that found something, `merge: human`, untrusted provenance and every denied-path or unreadable-listing reason still hold it (`mustHold` in `report-outcome.mjs`).
