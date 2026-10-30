---
bump: patch
---

### Changed

- The merge gate runs the shared YAML reader once per config text and key list in a process, not once per commit: the post-merge check reads the pipeline config at every merge since its floor, and those reads spawned about 14,600 reader processes per candidate. A replayed gate run on one candidate drops from 138 to 44 seconds of local work, with the same verdict.
