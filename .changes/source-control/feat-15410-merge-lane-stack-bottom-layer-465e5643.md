---
bump: patch
---

### Changed

- `reference/stacked-prs.md` says this marketplace's merge lane now lands only a stack's bottom layer, through the async merge once its `CI Status` is green, and that the issue lane does not stack yet.
- The babysit merge path's pin comment, posted before it asks GitHub to enqueue, says it is about to ask GitHub to enqueue the pull request and that GitHub can still refuse it. It used to say the pull request was enqueued, which stood beside a refusal GitHub sent in the same second. The pin's first line is unchanged, so `PIN_RE` still reads it.
