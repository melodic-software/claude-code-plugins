---
bump: patch
---

### Changed

- pr-verify's resolver looks up only the verdict names `write-verdict.mjs` writes, so it no longer looks up the head-ref digest names no writer produces: an unjudged head whose pull request links an issue takes 7 API calls instead of 11 (one with no linked issue, 3 fewer), and each other pull request at the head one lookup instead of two. The change that moves the writer to digest names adds those lookups back.
- The lost-run reconciler's spec pre-filter looks up a candidate's pass by the same written names, 2 lookups instead of 4.
