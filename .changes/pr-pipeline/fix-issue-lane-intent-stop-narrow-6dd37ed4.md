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
  no means framing, marked `security`, which holds as `security-risk` once that intake round is
  spent; the mark does not carry over to later runs, since intake triage re-judged it first.
