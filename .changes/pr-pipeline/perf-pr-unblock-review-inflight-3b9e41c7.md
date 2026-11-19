---
bump: patch
---

### Changed

- pr-unblock-dispatch no longer sends review-dependency for a Dependabot PR whose review-dependency run is still queued or going, as resolve-conflicts and fix-ci already do. Each such second dispatch queued a whole pr-unblock run behind the first. The run listing is read only for a PR about to be sent and is shared with the other passes.
- The dispatched-run stale-file check (`dispatcher-current.sh`, in pr-unblock.yml and pr-refine.yml) skips its contents read when the dispatcher ran the default branch tip itself, since that commit holds the tip's file.
