---
bump: patch
---

### Fixed

- The issue lane's already-done evidence (`done-evidence.mjs`) now counts a merged pull request whose merge commit is on the default branch even when its `base.ref` is another branch: an upper layer of a native stack keeps the lower layer's branch as its base when the stack lands together. Its merge commit must still close the issue.
