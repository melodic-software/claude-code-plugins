---
bump: patch
---

### Changed

- **One contract for `scripts/lane-telemetry-upsert.sh`.** Its arguments, writes, checks and exit codes now live once in `reference/lane-telemetry-upsert.md`; the work-loop and attend-queue `reference/telemetry-upsert.md` files keep only each lane's invocation and what it adds. The attend-queue copy had drifted (a shorter read-back description, no compound-command gotcha); both lanes now read the fuller text.
- **The work loop's instance-collision check is a generated copy of the shared `lib/lane-instance-collision-check.md`,** the same copy the babysit loop carries; no change to the check itself.
