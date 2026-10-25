---
bump: patch
---

### Changed

- `plugins` cache content check: only an install recorded at the marketplace clone's HEAD is compared. Every other install gets the new `not-at-head` verdict and is counted in a new `not_checked` field, not in `unverifiable`, so the answer no longer depends on how deep the clone is and nothing is fetched. The `sha-not-local` verdict is gone, and `no-clone-head` covers a clone whose HEAD names no commit. The sync digest carries `cache_content.not_checked`, and the `Cache content:` row and its tally sub-line render the count as `N not checked (recorded at an older commit)`.
