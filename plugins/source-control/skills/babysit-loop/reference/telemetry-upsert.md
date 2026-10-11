# Telemetry comment upsert (per-instance singleton, race-converging)

The exact upsert this lane runs at cycle-shape step 6 to maintain its ONE sentinel-identified status
comment **for this lane instance**. `SKILL.md`'s "Telemetry and durable loop state" owns where the
comment lives and what goes in it; this file owns how the singleton is maintained and how a creation
race converges.

The upsert is inlined in this plugin rather than invoked from `harness-ops` because an installed
plugin cannot invoke a sibling plugin's scripts.

Per the convention's lane-instance identity rule, the marker names the **writer**, not the lane
type: a marker naming only the lane makes two concurrent instances resolve one comment and
clobber each other's durable state. The id is `${user_config.lane_instance}`; a surviving literal
`${user_config.…}` placeholder means the key is unset, so fall back to the sanitized lowercased
hostname (headless-config floor: log the assumption). It is operator-supplied text about to be
interpolated into a shell string and a `jq` program, so it is validated and **rejected**, never
sanitized-and-continued. Substitute the resolved value for `<lane-instance>`; the check runs before
`MARKER` is built. The hostname fallback is a *default*, not a sanitizer: it passes through the
same gate, so a hostname that cannot produce a conforming id stops the lane rather than yielding a
marker nobody chose:

Run the upsert script ([GitHub](../../../reference/providers/github/babysit-loop/telemetry-upsert.md#upsert-script)) with the resolved id substituted for `<lane-instance>` and
`$REPO`, `$ISSUE` and `$BODY_FILE` set. In order, it:

1. Validates the instance id (`${user_config.lane_instance}`, else `hostname` lowercased with
   every other character turned to `-`) against `^[a-z0-9][a-z0-9-]{0,31}$`: empty, a leading
   hyphen, any other character, or over 32 characters is REJECTED with exit 1, never trimmed into
   something that looks valid. It then builds `MARKER` (`source-control:babysit-loop@<instance>`)
   and the sentinel line `$SENT` (`<!-- harness-ops:lane-telemetry marker=$MARKER -->`), which
   `$BODY_FILE` MUST open with.
2. Writes nothing when `$BODY_FILE` is empty, opens with a literal `@`, is not sentinel-prefixed,
   or carries under 16 payload bytes below the sentinel: fix the body composition, do not re-run
   blind.
3. Lists this instance's sentinel comments on the issue. A failed lookup skips the upsert this
   cycle (fail closed). An empty list creates one comment and re-lists; a failed re-list converges
   next cycle.
4. Writes the body to the canonical comment, the lowest id. No comment to write to (a create may
   have landed but was not re-found), a failed write, or a read-back that finds no well-formed
   telemetry body each mean: treat the lane as UNREPORTED and carry that forward to the next cycle,
   and do not trust the timestamp.
5. Only after the canonical write verifies, edits every other sentinel comment to the one-line
   tombstone `Superseded duplicate - canonical telemetry comment: <id>`.

**`$BODY_FILE` contract.** The file's FIRST line must be exactly `$SENT`, with the cycle's telemetry
below it. The lookup matches on that prefix, so a body composed without it is not merely rejected
here. It would never be found again, and the next cycle would post a second comment. Compose the
sentinel into the file; do not rely on anything downstream to add it.

**Body gate, write check, and read-back (encoded in the script).** Three checks, because they catch
different failures. The **pre-write** assertions run before any API call and reject a `$BODY_FILE`
that is empty, opens with a literal `@`, is not sentinel-prefixed, or carries under 16 payload bytes
below the sentinel, the mechanical form of the `@path`-as-body rule owned by the `harness-ops` lanes
skill, `/harness-ops:lanes` ("Never pass a body as an `@path` string"). The floor is measured on
everything below line 1, so it matches the wrapper's `MIN_BODY_BYTES` byte-for-byte whether that
line ends in LF or CRLF. The **write's own exit status** is checked next: a PATCH that fails leaves
the previous cycle's body in place, which a read-back running regardless would happily accept. The
**post-write** `VERIFY` then re-reads what the write stored, the only check that sees a write which
reported success and stored something else: a mangled body, a concurrent overwrite, a deleted
comment. It is also the only check that catches a defect in the invocation rather than the body
([GitHub](../../../reference/providers/github/babysit-loop/telemetry-upsert.md#upsert-script) names the one the script avoids).

Every branch that ends without a verified body says so and skips the duplicate-supersede pass, so a
cycle whose own write is unproven never tombstones a racing session's comment. A degraded body that
does land still moves the comment's timestamp, so any consumer keying on that timestamp rather than
on the body reads the lane as **fresh** while it carries nothing, which is why a refusal, a failed
write, and a failed verification all have to be carried forward: stderr does not survive the session,
and the next cycle must see that this one did not report. A lane with durable loop state records it
there; a lane without one carries it in the cycle's own summary.

Known limits, inherited from the wrapper: a PATCH that succeeds while storing the previous body still
verifies, and `VERIFY` asserts that *some* well-formed telemetry is present, not that *this* cycle's
write is what is present. Not replicated at all: the 64 KiB cap, the body-file containment checks,
retries, and the wrapper's distinct non-zero exit codes. Every branch here exits 0 and reports
through stderr alone.

**Creation race reconcile (encoded in the script).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone, only once the canonical write verifies, so
it never matches a lookup again. This covers a racer that died between its POST and its own
re-list, because the NEXT session's ordinary upsert performs the same reconcile. A crashed
racer's unmerged counters are an accepted loss (durable state re-derives over a cycle); nothing
is deleted. The reconcile converges duplicates **within one instance's own sentinel set**; a
sibling instance's comment carries a different marker and never enters `$LIST`, so it is neither
made canonical nor tombstoned.

## Instance-collision check (cycle start, before any write)

Partitioning is correct only while instance ids are distinct, so a collision is detected rather than
assumed away. `SKILL.md`'s state block carries the four fields this reads: `writer_nonce` is
generated once per session, `heartbeat_at` is rewritten every cycle, alongside `lane_instance` and
`paused_until`. After re-reading the block:

- No block at all → the marker is unclaimed. **Claim it before any work**: upsert a cycle-0 block
  carrying my nonce and heartbeat, immediately re-read, and run the creation-race reconcile above.
  If the canonical (lowest-id) comment for my marker then carries a different nonce, another
  session claimed the instance first. Take the live-collision branch below. Claiming first bounds
  the race to the claim itself: two same-id sessions starting together each stop before either has
  performed work or overwritten the other's first durable state.
- Nonce matches mine → ordinary continuation.
- Nonce differs **and** the block carries a non-null `restart_request` → **clean handoff.**
  Recording the request is a stopping lane's last write, so a fresh `heartbeat_at` beneath one is
  a stopped predecessor, not a live writer. Adopt the block, clear `restart_request`, write my
  nonce, continue, so a replacement launched right after a cycle-budget or expiry stop starts
  immediately instead of waiting out the staleness window.
- Nonce differs **and** the block is stale (`heartbeat_at` over **2 hours** old, and past
  `paused_until` when set) → an earlier session of this same instance restarted or died. Adopt the
  block, write my nonce, continue. This is the ordinary restart path. Two hours is twice the one-hour
  `ScheduleWakeup` ceiling, so a healthy lane at maximum idle backoff never reads as stale.
- Nonce differs **and** the block is fresh with no pending `restart_request` → **another live lane
  holds my instance id.** Write nothing to the block, escalate per the convention's escalation
  contract, and stop the loop cleanly.

`paused_until` is not `rate_limit_latch` and does not replace it: the latch says *do not claim
work*; `paused_until` says *do not read my silence as death*. Write it before entering a rate-limit
pause so a paused lane is never adopted as a dead one.

Report the instance on its own `instance:` line in the cycle report, never appended to `lane:`.
That reader's capture is `[a-z0-9_-]+` and would truncate the suffix at the `@`, rendering the lane
as if nothing were partitioned.

The legacy un-suffixed comment is never adopted, edited, or tombstoned: its marker names no writer,
so no instance can prove it owns it, and adopting it would reintroduce the shared-comment clobber
the partition removes. Retiring it is an operator action.
