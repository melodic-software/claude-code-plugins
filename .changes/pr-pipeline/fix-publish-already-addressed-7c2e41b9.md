---
bump: patch
---

### Fixed

- The write runner's script step accepts `feedback-already-addressed` from publish-feedback, so an
  earlier-fail round that finds every pr-verify note already addressed stops for a session as its
  route says. Before, the step rejected the reason and the run failed with `feedback-publish-failed`.
  A test now checks that every reason publish-feedback and its adjudication can write is one the
  step accepts.
