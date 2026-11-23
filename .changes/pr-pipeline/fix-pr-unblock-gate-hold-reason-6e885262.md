---
bump: patch
---

### Fixed

- `review-dependency-select` skips a Dependabot pull request whose only CI Status failure is the trust-gate hold as `awaiting-human`, with no model turn and no escalation, so it adds no human-gated label that would keep CI Status red after a trusted approval; its step summary says the lane did not judge the update's content. `dependency-escalate-security` now says the review chose owner reason `security` instead of asserting a HIGH or CRITICAL finding.
