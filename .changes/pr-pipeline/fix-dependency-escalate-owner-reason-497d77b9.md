---
bump: patch
---

### Fixed

- A review-dependency `escalate` verdict now names its owner reason (`owner_reason`, required by
  the verdict schema and `apply-dependency-verdict.mjs`). `intent`, `design`, `security` and
  `cost` escalate `dependency-escalate-<code>`, which holds for a person, and the hold comment
  carries the `stop-reason` marker and line for that code. `none` escalates
  `dependency-escalate-none`, routed `fail` with `needs-session`, so it never reaches the owner.
  A verdict without the field is invalid (`dependency-invalid`).
- Every pr-unblock `hold` row in `escalation-routes.json` now names its `owner-reason`, and each
  hold comment carries the `stop-reason` marker for it: the `feedback-*-security` rows,
  `feedback-question-security`, `dependency-security-close` and `dependency-fix-refused` (an
  untrusted-provenance trust hold) are `security`; `feedback-question-intent` and
  `feedback-question-design` are `intent` and `design`. `report-escalation.test.sh` fails any hold
  row without one. The retired `dependency-escalate` row is gone: an older comment carrying it
  reads as an unlisted reason, which still holds for a person.
