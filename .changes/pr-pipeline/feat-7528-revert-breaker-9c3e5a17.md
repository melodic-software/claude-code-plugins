---
bump: minor
---

### Added

- **A push to main that reverts a pull request the lanes App put in the merge queue now demotes that lane.** `post-merge-demotion-alert.yml` reads every commit the push brings (up to 20) for a `Reverts #N` or `This reverts commit <sha>` body line and files a `babysit-merge-demotion` record with signal `revert`; babysit makes no unattended merge while it is open, and only a person closing it re-enables the lane. A revert of a pull request a person queued files nothing.
