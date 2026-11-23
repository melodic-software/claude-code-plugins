---
bump: patch
---

### Fixed

- `review-dependency-select` skips a Dependabot pull request whose only CI Status failure is the trust-gate hold with the new `gate-hold` skip reason, with no model turn and no escalation, so it adds no human-gated label that would keep CI Status red after a trusted approval; its step summary says the lane did not judge the update's content. The dependency dispatcher does not record a `gate-hold` skip as handled, and sends review-dependency again once CI Status passes on that head. `dependency-escalate-security` now says the review chose owner reason `security` instead of asserting a HIGH or CRITICAL finding.
