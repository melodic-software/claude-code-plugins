---
bump: patch
---

### Fixed

- The issue lane holds a `pushback` only for a hold code (`security-risk`, `cost-risk`,
  `design-change`, `intent-change`) that opens its reason or names its cause, or for
  `"cause": "intent"` or `intent-change`, a cause read in any case, full-width letters included,
  with spaces, underscores or hyphens between its words and a trailing `.`, `:` or `;`. A reason
  that only mentions a security word no longer holds as `security-risk` on the first pushback; a
  reason opening with a `host-run` or `attended` code takes that row, or the `security-risk` hold
  when it names a security risk after the code. The rest are `pushback-means`, which goes back
  through intake triage once, where intake's own intent, security and cost rules still apply; one
  whose reason, summary, not-done item or cause names a security risk gets an intake comment with
  no means framing, marked `security`, and that mark is sticky: any later round that would fail
  (a spent intake, retry or wait, or a spent turn cap) holds as `security-risk` instead, and so
  does a `report-delivered` close, whose only evidence is the run's own claim; an `already-done`
  close still closes, since it needs a merged commit on the default branch.
