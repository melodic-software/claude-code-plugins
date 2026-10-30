---
bump: patch
---

### Fixed

- The issue lane holds a `pushback` as `intent` only when its outcome names `"cause": "intent"`,
  in any case. Any other pushback whose reason names a security concern or opens with a hold code
  takes that hold row; the rest are `pushback-means` in `stop-routes.json`, a choice of means or
  a design detail, which goes back through intake triage once.
