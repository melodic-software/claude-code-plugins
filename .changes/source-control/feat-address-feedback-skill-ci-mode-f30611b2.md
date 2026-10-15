---
bump: minor
---

### Added

- `/source-control:pull-request comments --ci` answers reviewer-bot threads unattended for the
  pr-unblock lane's `address-feedback` activity, through a review-thread tool the runner stages:
  it works only the threads the runner kept, edits only the files they name and never `.github/`,
  replies in a fixed template (disposition, `path:line` evidence, fix SHA, fenced prose with
  mentions and HTML comments broken), resolves a fixed VALID thread, leaves INCORRECT open, skips
  a thread that changed since the run read it, and runs no head code (#7032).
