---
bump: patch
---

### Fixed

- `work-resolve-issue` no longer writes `Hold: a human merges this` only because the runner's checks did not report (missing or for another tip). That line also failed `ci-status`, so pr-verify never ran and the PR waited on a person for checks `ci-status` reruns anyway. On a reused branch, a leak scan that is anything but `clean` (found, failed or missing) still holds it, since `lint-repo`'s gitleaks scan does not cover what the lane scan flags. A failed runner check, `merge: human`, untrusted provenance and every denied-path or unreadable-listing reason still hold it too (`mustHold` in `report-outcome.mjs`).
