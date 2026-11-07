---
bump: patch
---

### Fixed

- The post-merge check and the merge gate's in-flight count now add a merge they find on the
  re-read of page 1 that their walk of merged pull requests missed, instead of failing the whole
  read as "the history changed while it was read". Pages follow the update time, so a pull request
  updated or merged during the walk can only have moved to page 1, which the re-read holds. Before,
  a merge or an update to a merged pull request during the walk made the check unreadable, and a
  pr-merge sweep then held every lanes App pull request with "the lane's room could not be read".
