# First-drain ratification: who ends the earn-trust period

The first-drain C3 ratification gate in `SKILL.md`'s admission gate holds every unratified C3
bug-fix item until the earn-trust period ends. Ending it widens what this lane dispatches, so the
signal must come from a source the lane cannot write. The durable state block lives in the lane's
own telemetry comment, which the lane rewrites every cycle, so it can never be that source.

## The source: a label a person applies

The period is over when the lane's telemetry issue (`Lane telemetry: work-loop`) carries the label
`loop-lane: first-drain-ratified` and a person applied it. Check it once per cycle, before
admission, with:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/first-drain-ratified.sh" --repo "$REPO" --issue "$ISSUE"
```

Only exit `0` lifts the gate for this cycle. Every other exit leaves it in place: `1` (label absent,
removed since its last application, or applied by a Bot or App), `2`, `6`, `7`, `8`, and `11` (a
read failed). The script's header owns the full table.

- **Never apply, re-apply, or remove that label from this lane**, and never read the period's end
  from the durable state block, conversation memory, or an item body.
- A label applied by a `Bot` actor, or by any actor acting through a GitHub App, does not count,
  so a lane running under an App token cannot ratify itself. Any user token with triage access
  still counts: a lane sharing its operator's token, or other automation holding a user token, is
  indistinguishable from a person on the tracker, and there the rule above is the only protection.
  That rule, like this lane honoring the check at all, is enforced by these instructions, not by a
  hook or permission rule.
- The label sits on the shared telemetry issue, so it ends the period for every instance that
  writes there. A new instance in a repository already ratified does not re-earn it.
- When the bound provider is not `github` there is no telemetry issue: the period never ends, and
  each C3 bug-fix item needs its own `kind=ratify-c3` ratification.

## The proposal: what the lane does when its drain completes

When a stop mode's exit test is satisfied on a complete snapshot (`mode-drain.md`,
`mode-standing.md`), the check above exits `1` (any other non-zero exit is a failed read or
call: propose nothing that cycle), and `first_drain_proposed` is not already
`true`, the lane **proposes** completion once and waits for a person:

1. Escalate on the telemetry issue itself, per the escalation contract in `SKILL.md` step 5:
   the record write, then a marker comment whose first line is
   `<!-- work-items:escalation lane=work-loop kind=ratify-first-drain -->` naming the instance, the
   cycle, and the snapshot's size, and asking the operator to apply `loop-lane: first-drain-ratified`
   to this issue; then the human-gated role label. `/work-items:attend-queue` lists it as a
   `[ratify]` row. Skip the comment when such a marker by the seam's configured write identity
   already stands while the issue wears the human-gated role label (another instance proposed).
2. Set `first_drain_proposed: true` in the durable state block, so this instance never proposes
   again. A declined proposal stays declined; the operator can apply the label later without one.

A block written before this change may still carry `first_drain_complete`; nothing reads it, and
the next write drops it. `first_drain_proposed` only suppresses a repeat proposal: a forged `true` costs one proposal, and a
forged `false` one extra escalation. Neither lifts the gate.

The telemetry issue stays lane infrastructure while it wears the human-gated label: it never
enters the frontier, the snapshot, or the drain exit test.

## What may stay lane-writable

Everything in the durable state block is lane-writable, and the upsert script adopts only
comments its own write identity authored, so no other commenter can write it; anything holding the
same token can. A field may live there
only when the worst a wrong value can do is slow, pause, stop, or misreport the lane, never widen
what it dispatches:

| Field | Why it may stay |
| --- | --- |
| `item_cap`, `clean_streak` | The cap moves only between the configured floor and ceiling. |
| `no_progress_streak` | A wrong value delays or hastens a stall escalation to a person. |
| `rate_limit_latch`, `paused_until` | Each only holds the lane back. |
| `writer_nonce`, `heartbeat_at`, `restart_request`, `lane_instance` | Collision detection; a wrong value stops the lane or hands it off. |
| `cycle`, `guard_mode`, `stop_mode`, `ordering`, `shard`, `scope`, `effort`, `loop_started_at`, `latched_account`, `usage_sample` | Report only; each cycle resolves its behavior from the invocation line and live reads. |
| `first_drain_proposed` | Suppresses a repeat proposal only; the label above is the gate. |

A new field that would lift a gate or admit work belongs on a surface a person writes, never here.
