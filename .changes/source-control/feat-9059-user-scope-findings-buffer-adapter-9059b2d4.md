---
bump: patch
---

### Changed

- The babysit-loop promotion-evidence helper's settings reader, `skills/babysit-loop/scripts/operator-options.mjs`, is now generated from the repository's shared `lib/plugin-options.mjs`. `resolve-promotion-evidence.mjs` passes its five option keys to the reader, so which settings it reads, and when it fails closed, are unchanged.
