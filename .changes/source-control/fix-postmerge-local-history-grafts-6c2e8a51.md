---
bump: patch
---

### Fixed

- The merge gate's local read of the pipeline file's history ignores graft files and never lazy-fetches a missing commit, as the post-merge ancestry check already did, so a clone with a graft cannot move the post-merge floor. A partial clone, which lacks older blobs, leaves the read to the API as a shallow one does. A shared post-merge answer refused as `config-unreadable` no longer writes a recompute back over the run's answer.
