---
bump: patch
---

### Fixed

- The issue lane holds a `pushback` for a person only when its outcome names `"cause": "intent"`.
  Any other pushback is `pushback-means` in `stop-routes.json`: a choice of means or a design
  detail the lane decides on evidence, which retries at most once and then fails, never reaching
  a person.
