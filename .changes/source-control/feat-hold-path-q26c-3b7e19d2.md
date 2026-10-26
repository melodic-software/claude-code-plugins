---
bump: minor
---

### Changed

- `babysit_risk` splits its path floor by class (`FLOOR_CLASSES`): `HIGH_FLOOR` is now the `trust` and `gate` globs, and an `enforcement` glob (`REVIEW_FLOOR`) scores HIGH as `review-path:<glob>` unless the security lane's evidence is bound to the head with no open finding (`security_review_clean`). A clean code-review lane alone clears nothing. `NEVER_FLOOR_EXEMPT` keeps every floor glob.
