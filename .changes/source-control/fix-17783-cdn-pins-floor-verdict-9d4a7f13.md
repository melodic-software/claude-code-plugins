---
bump: patch
---

### Fixed

- babysit-prs: a Dependabot CDN-pin bump carrying the lanes App's pins sync commit no longer waits for a person. When its one trust-gate path is `lib/cdn-pins/pins.json`, modified in place, `CI Status` clears the hold once the lanes App's newest review-dependency round marker names the head with `verdict=merge` (owner decision Q154 A). Until then it fails with `#<n> by Dependabot changes only the CDN pins record on trust-gate paths`, which review-dependency reviews rather than skipping as `gate-hold`. Any other trust-gate path, a rename, a marker for another head or by another account, or an unreadable read keeps the hold.
