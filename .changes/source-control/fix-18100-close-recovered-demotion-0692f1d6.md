---
bump: patch
---

### Fixed

- A schedule or dispatch demotion record that `babysit_postmerge.py --remediate` files now says it clears once a full run passes on main at a later commit and a lane then closes it, rather than that it clears itself.
