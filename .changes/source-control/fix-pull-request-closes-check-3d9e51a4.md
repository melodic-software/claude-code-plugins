---
bump: patch
---

### Fixed

- `/source-control:pull-request` `create` checks each issue the body would close against the diff before writing it: an issue with a done-when item not delivered moves to `Refs: #N` with a `## Remaining` section, and closing keywords appear only on the linkage line. `ready` runs the same check on GitHub's closing references before the flip and leaves the PR in draft on an over-claim.
