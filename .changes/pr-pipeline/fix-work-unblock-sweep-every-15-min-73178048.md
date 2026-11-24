---
bump: patch
---

### Fixed

- The scheduled `work-unblock` sweep runs every 15 minutes (`:04`, `:19`, `:34`, `:49`) instead of once at `:54`, so one sweep lands within 15 minutes of the GITHUB_TOKEN window reset, whose minute drifts from day to day. Deferred issues re-fire where the start gate's projection lets them start. `publish-lane-level` still decides once an hour, on the `:49` run only.
