---
bump: patch
---

### Changed

- `changelog apply --ci` now says the calling workflow files a release's handoffs as one issue, with
  one checklist item per handoff. A `cap-exceeded` plan's issue names its `stop_reason`, and the
  release is marked done once that issue holds every handoff; a `range-not-computed` plan files
  nothing and the next run takes the release again.
