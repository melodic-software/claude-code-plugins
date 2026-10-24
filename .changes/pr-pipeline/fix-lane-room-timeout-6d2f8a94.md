---
bump: patch
---

### Fixed

- `enable-auto-merge` checks out the default branch with full history, as the post-merge check and the merge job do, so the room's post-merge recompute decides containment locally instead of making a compare API call per lane record. The lane-room read also has its own 8 minute timeout, apart from the verifier reads' 4 minutes, and a timeout still holds the lane. The arm step's timeout is now 18 minutes and the job's 30.
