---
bump: patch
---

### Fixed

- ci-status's merge-group verdict reader plans its read floor to GITHUB_TOKEN's live header limit instead of github-token's 1,000-call `limit-cap`, keeping the 10% `read-floor`, and its cold-read gate reserves that same floor (owner decision D418). Run 44463304120 ejected 21 merge-group runs with 2,766 of 5,000 requests left.
