---
bump: patch
---

### Fixed

- `list-promotion-candidates.js` run as a CLI now prints a malformed or missing claim inventory error (with the session format hint) as one line on stderr and exits 1, instead of an uncaught exception with a Node stack trace. The `listPromotionCandidates` function still throws for programmatic callers.
