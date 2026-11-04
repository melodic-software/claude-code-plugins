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
