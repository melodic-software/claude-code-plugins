---
bump: patch
---

### Fixed

- The scheduled `work-unblock` sweep runs every 15 minutes (`:13`, `:28`, `:43`, `:58`) instead of once at `:54`, so one sweep lands within 15 minutes of the GITHUB_TOKEN window reset, whose minute drifts from day to day. The minutes share no hourly schedule with another workflow. Deferred issues re-fire where the start gate's projection lets them start. `publish-lane-level` still decides once an hour, on the `:28` run only.
