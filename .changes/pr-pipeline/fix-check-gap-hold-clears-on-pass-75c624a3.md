---
bump: patch
---

### Fixed

- `work-resolve-issue` no longer writes `Hold: a human merges this` on a reuse PR only because the runner's checks or its leak scan did not report (missing, for another tip, `failed` or no word). That line also failed `ci-status`, so pr-verify never ran and the PR waited on a person for a check CI runs anyway. Such a PR is now armed by `enable-auto-merge` only on a pr-verify pass and a bound security review with no CRITICAL finding at its head, and merges once `ci-status` passes. A failed runner check, a leak scan that found something, `merge: human`, untrusted provenance and every denied-path or unreadable-listing reason still hold it (`mustHold` in `report-outcome.mjs`).
