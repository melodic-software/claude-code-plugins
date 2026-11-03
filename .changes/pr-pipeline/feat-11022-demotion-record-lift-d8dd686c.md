---
bump: minor
---

### Changed

- A `revert` demotion record that `post-merge-demotion-alert.yml` files now says it lifts once a pull request that references it merges into main (the merge gate's `_lifted_at`), not only on a person's close. The pr-pipeline README states the revert and read-back lift and why a canary record stays human-close.
