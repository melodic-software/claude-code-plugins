---
bump: patch
---

### Fixed

- `review-dependency-select` holds a Dependabot pull request whose only CI Status failure is the trust-gate hold as `dependency-gate-hold`, with no model turn: the hold names no owner reason and says the lane did not judge the update's content. `dependency-escalate-security` now says the review chose owner reason `security` instead of asserting a HIGH or CRITICAL finding.
