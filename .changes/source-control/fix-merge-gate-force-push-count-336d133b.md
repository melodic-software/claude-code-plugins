---
bump: patch
---

### Fixed

- The merge gate's force-push read no longer fails on a pull request that
  changes a lane source and has any timeline item that is not a force push.
  GitHub's `totalCount` on a `timelineItems` connection counts every item,
  whatever `itemTypes` names, so the read now treats the listing as whole only
  when its last page answers `hasNextPage: false`, and raises on a page whose
  pagination answer is missing or malformed.
