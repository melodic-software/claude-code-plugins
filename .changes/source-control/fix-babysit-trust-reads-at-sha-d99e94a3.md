---
bump: patch
---

### Fixed

- The babysit merge gate reads the trusted-actor list and the admission rules at the tip commit of their branch, resolved by its full ref through `base_tip`, never by the branch name, so a tag named like the branch cannot supply them. The escalation lift reads the trusted list the same way, and the verdict answer key names both files by `refs/heads/<branch>`. A branch whose tip does not resolve to a commit SHA fails closed: the verdict read is unreadable and the label stays on.
