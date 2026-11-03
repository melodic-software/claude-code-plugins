---
bump: patch
---

### Fixed

- pr-unblock's `report-stop-status` posts the stop status on the commit the activity's push job
  pushed (`apply-conflict-patch`, `apply-feedback-patch`, `apply-dependency-patch`), and on the
  select job's head only when that job pushed none. A reply or verdict job that stopped after the
  push, such as `publish-feedback` with `feedback-unadjudicated`, put the failing status on the
  head before it, so the pull request's head carried none, ci-status passed and pr-merge armed
  auto-merge over the stop.
