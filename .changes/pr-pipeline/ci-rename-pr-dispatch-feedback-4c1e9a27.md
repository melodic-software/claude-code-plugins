---
bump: patch
---

### Changed

- The convention names the renamed workflow `pr-dispatch-feedback.yml` (display name
  `PR Dispatch Feedback`), in place of `pr-feedback-dispatch.yml`. Its `pr-feedback-dispatched-*`
  artifact names are unchanged.
- The dispatcher's half-hourly recovery and the lost-run reconciler also read runs under the file's
  earlier name, since a run keeps the path it started from. Each costs one more run listing per
  pass.
