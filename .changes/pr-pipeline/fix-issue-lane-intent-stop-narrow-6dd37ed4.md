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
  whose reason, summary or cause names a security risk gets an intake comment with no means
  framing, marked `security`, and that mark is sticky: the next intake round past the cap, a
  plain pushback or a `split-required` skip included, holds as `security-risk` instead of failing.
