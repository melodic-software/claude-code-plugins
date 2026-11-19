<!-- GENERATED from lib/lane-instance-collision-check.md by scripts/sync-shared-copies.sh. Do not edit this copy:
edit the canonical source, then rerun the script. -->

# Instance-collision check (cycle start, before any write)

A lane's telemetry marker names its instance, so partitioning is correct only while instance ids
are distinct; a collision is detected rather than assumed away. The lane's durable state block
carries the four fields this reads: `writer_nonce`, generated once per session; `heartbeat_at`,
rewritten every cycle; `lane_instance`; and `paused_until`. After re-reading the block through the
lane's upsert script:

- No block at all → the marker is unclaimed. **Claim it before any work**: upsert a cycle-0 block
  carrying my nonce and heartbeat, immediately re-read, and run the creation-race reconcile. If the
  canonical (lowest-id) comment for my marker then carries a different nonce, another session
  claimed the instance first: take the live-collision branch below. Claiming first bounds the race
  to the claim itself: two same-id sessions starting together each stop before either has performed
  work or overwritten the other's first durable state.
- Nonce matches mine → ordinary continuation.
- Nonce differs **and** the block carries a non-null `restart_request` → **clean handoff.**
  Recording the request is a stopping lane's last write, so a fresh `heartbeat_at` beneath one is a
  stopped predecessor, not a live writer. Adopt the block, clear `restart_request`, write my nonce,
  continue, so a replacement launched right after a cycle-budget or expiry stop starts immediately
  instead of waiting out the staleness window.
- Nonce differs **and** the block is stale (`heartbeat_at` over **2 hours** old, and past
  `paused_until` when set) → an earlier session of this same instance restarted or died. Adopt the
  block, write my nonce, continue. This is the ordinary restart path. Two hours is twice the longest
  self-paced wait, so a healthy lane at maximum idle backoff never reads as stale. Pointer:
  [scheduled tasks: let Claude choose the interval](https://code.claude.com/docs/en/scheduled-tasks#let-claude-choose-the-interval).
  Recheck trigger: that section's longest delay grows past half the two-hour window.
- Nonce differs **and** the block is fresh with no pending `restart_request` → **another live lane
  holds my instance id.** Write nothing to the block, escalate per the convention's escalation
  contract, and stop the loop cleanly.

`paused_until` is not `rate_limit_latch` and does not replace it: the latch says *do not claim
work*; `paused_until` says *do not read my silence as death*. Write it before entering a rate-limit
pause so a paused lane is never adopted as a dead one.

Report the instance on its own `instance:` line in the cycle report, never appended to `lane:`. The
telemetry reader's lane capture is `[a-z0-9_-]+` and would truncate the suffix at the `@`,
rendering the lane as if nothing were partitioned.
