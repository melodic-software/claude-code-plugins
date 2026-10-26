---
bump: minor
---

### Added

- `/source-control:pull-request create` builds the `Summary` section's Problem and intent line from the linked item's `Problem:` and `- Intent (why, in the user's words):` lines when no local plan is found, reading the body from the GitHub issue read or, with a work-item tracker bound, `/work-items:track view`. A found plan still wins; the item text is framed as data and gets the plan line's shape and scrub, minus any closing keyword or `@` mention.
