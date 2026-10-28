---
bump: patch
---

### Fixed

- `work-resolve-issue` no longer writes `Hold: a human merges this` only because the runner's checks did not report (missing or for another tip). That line also failed `ci-status`, so pr-verify never ran and the PR waited on a person for a check CI runs anyway. Such a PR is now armed by `enable-auto-merge` only on a pr-verify pass and a bound security review with no CRITICAL finding at its head, and merges once `ci-status` passes. A failed runner check, `merge: human`, untrusted provenance, every denied-path or unreadable-listing reason, and on a reuse PR a leak scan that is anything but `clean` (found, failed, missing or unread) still hold it (`mustHold` in `report-outcome.mjs`).
