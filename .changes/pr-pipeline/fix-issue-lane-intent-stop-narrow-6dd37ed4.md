---
bump: patch
---

### Fixed

- The issue lane holds a `pushback` only for a hold code (`security-risk`, `cost-risk`,
  `design-change`, `intent-change`) that opens its reason or names its cause, or for
  `"cause": "intent"` or `intent-change` in any case, with an underscore or space accepted for the
  hyphen. A reason that only mentions a security word no longer holds as `security-risk`; a
  reason opening with a `host-run` or `attended` code takes that row. The rest are
  `pushback-means`, which goes back through intake triage once, where intake's own intent,
  security and cost rules still apply.
