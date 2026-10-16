---
bump: minor
---

### Added

- `/source-control:pull-request comments --ci` answers reviewer-bot threads unattended for the
  pr-unblock lane's `address-feedback` activity, through a review-thread tool the runner stages:
  it works only the threads the runner kept, edits only the files they name and never `.github/`,
  commits its fixes, and records one templated disposition per thread (disposition, `path:line`
  evidence, fix SHA, prose note). It posts nothing and runs no head code; a later job with no
  model validates the recorded replies and posts them (#7032).
