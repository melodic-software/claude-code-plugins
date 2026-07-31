# Telemetry comment upsert (per-instance singleton, race-converging)

The exact upsert this lane runs at cycle-shape step 6 to maintain its ONE sentinel-identified status
comment **for this lane instance**. `SKILL.md`'s "Telemetry and durable loop state" owns where the
comment lives and what goes in it; this file owns how the singleton is maintained and how a creation
race converges.

The upsert is inlined in this plugin rather than invoked from `claude-ops` because an installed
plugin cannot invoke a sibling plugin's scripts.

Per the convention's lane-instance identity rule, the marker names the **writer**, not the lane type
(#1295): a marker naming only the lane makes two concurrent instances resolve one comment and
clobber each other's durable state. The id is `${user_config.lane_instance}`; a surviving literal
`${user_config.…}` placeholder means the key is unset, so fall back to the sanitized lowercased
hostname (headless-config floor: log the assumption). It is operator-supplied text about to be
interpolated into a shell string and a `jq` program, so it is validated and **rejected**, never
sanitized-and-continued. Substitute the resolved value for `<lane-instance>`; the check runs before
`MARKER` is built. The hostname fallback is a *default*, not a sanitizer — it passes through the
same gate, so a hostname that cannot produce a conforming id stops the lane rather than yielding a
marker nobody chose:

```bash
INSTANCE="<lane-instance>"   # ${user_config.lane_instance}, else `hostname` sanitized
[ -n "$INSTANCE" ] || INSTANCE="$(hostname | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9-' '-')"
# ^[a-z0-9][a-z0-9-]{0,31}$ — empty, a leading hyphen, any other character, or
# over 32 chars is REJECTED, never trimmed into something that looks valid.
case "$INSTANCE" in
"" | -* | *[!a-z0-9-]*)
  echo "telemetry: lane_instance '$INSTANCE' is not ^[a-z0-9][a-z0-9-]{0,31}\$; refusing to build a marker" >&2
  exit 1
  ;;
esac
[ "${#INSTANCE}" -le 32 ] || {
  echo "telemetry: lane_instance '$INSTANCE' exceeds 32 characters; refusing to build a marker" >&2
  exit 1
}
MARKER="source-control:babysit-loop@$INSTANCE"
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # first line of $BODY_FILE
LOOKUP() { gh api --paginate "repos/$REPO/issues/$ISSUE/comments" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id"; }
if ! LIST=$(LOOKUP); then
  echo "telemetry: comment lookup failed; skipping upsert this cycle (fail closed)" >&2
else
  if [ -z "$LIST" ]; then
    gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE" >/dev/null
    LIST=$(LOOKUP) || LIST=""   # re-list; a failure here converges next cycle
  fi
  CANON=$(printf '%s\n' "$LIST" | sort -n | head -n1)
  if [ -n "$CANON" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$CANON" -F body=@"$BODY_FILE"
    for DUP in $(printf '%s\n' "$LIST" | sort -n | tail -n +2); do
      gh api -X PATCH "repos/$REPO/issues/comments/$DUP" \
        -f body="Superseded duplicate - canonical telemetry comment: $CANON" || true
    done
  fi
fi
```

**Creation race reconcile (encoded above).** Two sessions racing the first-ever upsert can both
see an empty lookup and both POST, forking the singleton. The upsert converges every cycle
duplicates are visible: the LOWEST comment id is canonical (numeric sort, deterministic for
every session), the canonical comment receives the current cycle's full state, and every other
sentinel comment is edited to a one-line tombstone so it never matches a lookup again — this
covers a racer that died between its POST and its own re-list, because the NEXT session's
ordinary upsert performs the same reconcile. A crashed racer's unmerged counters are an
accepted loss (durable state re-derives over a cycle); nothing is deleted. The reconcile converges
duplicates **within one instance's own sentinel set** — a sibling instance's comment carries a
different marker and never enters `$LIST`, so it is neither made canonical nor tombstoned.

## Instance-collision check (cycle start, before any write)

Partitioning is correct only while instance ids are distinct, so a collision is detected rather than
assumed away. `SKILL.md`'s state block carries the four fields this reads: `writer_nonce` is
generated once per session, `heartbeat_at` is rewritten every cycle, alongside `lane_instance` and
`paused_until`. After re-reading the block:

- No block at all → the marker is unclaimed. **Claim it before any work**: upsert a cycle-0 block
  carrying my nonce and heartbeat, immediately re-read, and run the creation-race reconcile above.
  If the canonical (lowest-id) comment for my marker then carries a different nonce, another
  session claimed the instance first — take the live-collision branch below. Claiming first bounds
  the race to the claim itself: two same-id sessions starting together each stop before either has
  performed work or overwritten the other's first durable state.
- Nonce matches mine → ordinary continuation.
- Nonce differs **and** the block carries a non-null `restart_request` → **clean handoff.**
  Recording the request is a stopping lane's last write, so a fresh `heartbeat_at` beneath one is
  a stopped predecessor, not a live writer. Adopt the block, clear `restart_request`, write my
  nonce, continue — a replacement launched right after a cycle-budget or expiry stop starts
  immediately instead of waiting out the staleness window.
- Nonce differs **and** the block is stale (`heartbeat_at` over **2 hours** old, and past
  `paused_until` when set) → an earlier session of this same instance restarted or died. Adopt the
  block, write my nonce, continue — the ordinary restart path. Two hours is twice the one-hour
  `ScheduleWakeup` ceiling, so a healthy lane at maximum idle backoff never reads as stale.
- Nonce differs **and** the block is fresh with no pending `restart_request` → **another live lane
  holds my instance id.** Write nothing to the block, escalate per the convention's escalation
  contract, and stop the loop cleanly.

`paused_until` is not `rate_limit_latch` and does not replace it: the latch says *do not claim
work*; `paused_until` says *do not read my silence as death*. Write it before entering a rate-limit
pause so a paused lane is never adopted as a dead one.

Report the instance on its own `instance:` line in the cycle report, never appended to `lane:` —
that reader's capture is `[a-z0-9_-]+` and would truncate the suffix at the `@`, rendering the lane
as if nothing were partitioned.

The legacy un-suffixed comment is never adopted, edited, or tombstoned: its marker names no writer,
so no instance can prove it owns it, and adopting it would reintroduce the shared-comment clobber
the partition removes. Retiring it is an operator action.
