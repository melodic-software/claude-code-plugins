---
bump: patch
---

### Fixed

- The README, `pr-run-activity.md` and `pr-pipeline.yaml` no longer call the `work-unblock` sweep hourly: it runs every 15 minutes, and only its `publish-lane-level` job stays hourly. The README's new "The work-unblock sweep" section holds what `work-unblock.yml`'s header and trigger comments said about the sweep, including the `workflow_run` and `workflow_dispatch` safety limits; those comments are now a link to it.
