---
bump: patch
---

### Changed

- check-wip-cap takes `reads: pause`, which makes only the open lane PR listing and the merged count, the two searches `capped` depends on, and leaves the admission fields unread (`admission_basis` `not-read`, `admission-open` `true`). work-resolve-issue's pick-slot and work-unblock's hourly state save pass it: neither reads anything but the pause, and each used to spend the admitted count, the queued listing, a pull request read per lane PR whose first body line names no issue, and up to 30 blocker reads (26 GITHUB_TOKEN calls in one pick-slot run with 19 issues queued; 5 now, whatever the queue: the two searches and resolve-config's three issue reads). Every other caller still reads all.
- pr-verify's resolve-pr looks up the FAIL names at a head before this pull request's pass names, and weighs a pass against the spec before looking up the FAIL named with the pull request's issues. Each path whose reads succeed resolves as before, and the new order makes a subset of the old lookups, so a failed lookup the old order would have reached can now be skipped; a FAIL named without issues now costs 5 calls instead of 9, and a pass whose spec is unchanged 11 instead of 13.
