---
bump: patch
---

### Changed

- The demotion record read (`read_demotion`), behind the post-merge check's floor, the merge gate and the lane room, reads its records 20 issues to a GraphQL query instead of one each, and reads on its own any record a batch fails or leaves out, so its answer is unchanged. On this repository's 39 candidate issues it took 5 calls instead of 42.
