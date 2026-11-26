---
bump: patch
---

### Fixed

- The babysit merge gate's cost-decision lane vetting (`babysit_merge_policy._noticed_head`) no longer holds every lane run on a head whose compare lists 300 files or more: past the compare API's cap it compares the review-lane workflows' blobs at the compare's merge base and the head, and still holds when either listing cannot be read.
