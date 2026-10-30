---
bump: minor
---

### Added

- **A push to main that reverts a pull request the lanes App put in the merge queue now demotes that lane.** `post-merge-demotion-alert.yml` reads every commit each canary push run brings (up to 20), whatever the run concluded, for a `Reverts #N` line, a revert-button subject, `This reverts commit <sha>` or the red-main bot's culprit marker, and files a `babysit-merge-demotion` record with signal `revert`; babysit makes no unattended merge while it is open, and only a person closing it re-enables the lane. A revert of a pull request a person queued files nothing, and a revert commit an existing record lists is never filed again.
