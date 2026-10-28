---
bump: patch
---

### Changed

- pr-verify's resolver looks up only the verdict names `write-verdict.mjs` writes, so it no longer looks up the head-ref digest names no writer produces: an unjudged head takes 7 API calls instead of 11, and each other pull request at the head one lookup instead of two. The change that moves the writer to digest names adds those lookups back.
