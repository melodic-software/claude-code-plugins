---
bump: patch
---

### Fixed

- The merge-risk hold floor now covers `.github/scripts/pr-unblock/verify-notes.mjs` as an enforcement path, since it adds and removes the `pr-verify-failed` merge hold. An edit to it is held like the other pr-unblock enforcement scripts.
