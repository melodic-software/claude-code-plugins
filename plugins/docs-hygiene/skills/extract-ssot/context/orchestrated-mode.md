# Orchestrated whole-repo mode

## Contents

- [Roles](#roles)
- [Worker tiering](#worker-tiering)
- [Concurrency — static, conservative, capped](#concurrency--static-conservative-capped)
- [Rate-limit guard integration (when present)](#rate-limit-guard-integration-when-present)
- [Cadence and commits](#cadence-and-commits)
- [Cross-references](#cross-references)

Defaults for running the extract-ssot pipeline at whole-repo scale —
hundreds to thousands of tracked markdown files, dozens of candidate
clusters — where identify/verify/execute becomes a multi-agent batch
rather than a handful of inline actions. Loaded by the confirm-scope
gate (SKILL.md "Bare invocation: confirm scope first") when the user
opts into a whole-repo run, and by `actions/batch.md` Step 6 when
sizing dispatches.

Private surface — external consumers invoke
`/docs-hygiene:extract-ssot`, never cite this file directly (contract:
`/docs-hygiene:audit-encapsulation`).

## Roles

- **The orchestrating session owns the loop, not the work.** It holds
  the roster, the wave plan, the commit cadence, and the abort
  thresholds (`actions/batch.md` Step 2); workers hold the per-cluster
  work. It never performs a cluster's verify or execute inline while
  workers are available — its context is the scarcest resource in the
  run.
- **Inventory is ONE read-only survey subagent**, not a fan-out. The
  survey's output is unverified synthesis whatever its size, so extra
  survey workers multiply lead lists, not evidence; the verify phase is
  where breadth belongs.
- **Verify and execute run as worker agents.** Verify workers are
  read-only; execute workers edit call sites per the wave plan.

## Worker tiering

Verify and execute are judgment stages (gate rulings, wrong-abstraction
calls, prose rewrites), so workers there run a strong general-purpose
tier — as of 2026-08 that means an Opus-class model (example, not a
pin; resolve the current tier names from the platform's model docs at
run time). Mechanical stages — phrase sweeps, lint passes, count
scripts — run cheaper tiers or plain scripts. Never let the whole fleet
silently inherit the orchestrator's tier: at fleet volume, every notch
of over-provisioning multiplies.

## Concurrency — static, conservative, capped

Default worker concurrency is **2**, applied as a hard cap in the
dispatch loop (pairs of workers, sequential between pairs). The default
is deliberately static and low:

- Most consumers run under **shared subscription rate-limit windows**
  (5-hour and 7-day). The windows are machine- and account-wide: other
  concurrent sessions draw on them invisibly, so an orchestrator that
  cannot observe the windows must assume contention.
- Enterprise and API-key auth expose no window data at all
  (capability-detect fails open to "unknown"), which is a reason for
  MORE conservatism, not less.
- Remote/cloud containers cannot see machine-scope guard state (below),
  so they always operate in unknown mode.

The user may raise the cap for a run; the orchestrator never raises it
on its own, and a rate-limit error observed mid-run drops the batch to
fully sequential for its remainder.

## Rate-limit guard integration (when present)

When the consuming machine runs the `rate-limit-guard` plugin, its tee
snapshot makes the windows observable, and this mode consumes it
between wave dispatches: before dispatching each wave (and each pair
within a wave), read the snapshot; on a trip, finish in-flight workers,
dispatch nothing new, and pause until the pause end. The operable floor
below is inlined **verbatim** per the loop-lane convention's
inline-floor rule (byte-identical across consumers and to the reader
contract's floor); provenance is the `rate-limit-guard` plugin's reader
contract (`plugins/rate-limit-guard/reference/reader-contract.md` in
the marketplace repository) — cited for provenance only, since an
installed plugin cannot read a sibling plugin's files at runtime.

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from a
  fresh snapshot stays valid through the pause (no refresh happens while paused). While paused, a
  consumer **must** arm a session Monitor on the tee file and re-evaluate on every write — the file
  carries **no account-identifier field**, so a write is the only signal that the windows changed
  under you (account switch, another session's refresh).
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.

**Capability detection (fail-open), scoped like the reader contract:**

| Observation | Scope | Mode |
| --- | --- | --- |
| Fresh snapshot with plausible `rate_limits` | whole guard | **proactive** — apply the operable floor |
| Tee file absent, stale, or missing `rate_limits` | whole guard | **unknown → reactive-only** |
| Absurd `used_percentage` or `resets_at` on one window | that window | that window **unknown**; keep applying the floor to every window still plausible |
| No window plausible | whole guard | **unknown → reactive-only** |

One malformed window must not suppress a valid sibling: if the five-hour record is absurd but the
seven-day window is plausible and already ≥ 90, pause on the seven-day trip (and vice versa). Only
the whole-guard rows above drop the run to reactive-only.

**Reactive-only mode:** keep the static concurrency cap, never fabricate a pause from untrusted
data, and react to (a) detection records in `~/.claude/rate-limit-guard/stop-events.jsonl` (read on
entering reactive-only and again before each new work claim; records newer than this session's
start — later, newer than the last resume baseline — are live signal) and (b) rate-limit error text
this session itself sees. Resume timing comes from that error text where available, otherwise
backoff-and-retry. A later fresh snapshot with plausible windows upgrades the run back to
proactive checks. Dynamic *scaling* (raising the cap when windows are healthy) is deliberately out
of scope: with no account identifier in the snapshot and other sessions' burn invisible between
refreshes, headroom is a weaker signal than a trip, and the cost of over-shooting a shared window
lands on every session on the machine.

## Cadence and commits

Waves land **wave-committed**: each wave's migrations are one
conventional-format commit on the task branch, so the batch reviews
wave-by-wave and a mid-run abort loses at most one wave. Sequencing
within and between waves stays owned by `actions/batch.md` (overlap
matrix, sequential-by-default); this file only adds the concurrency
ceiling and the guard check between dispatches.

## Cross-references

- SKILL.md "Bare invocation: confirm scope first", the gate that
  routes a whole-repo opt-in here
- `actions/identify.md` — the single-survey inventory this mode retains
- `actions/batch.md` — wave grouping and dispatch policy (Step 6)
- `docs/conventions/loop-lane/README.md` §6 (marketplace repository) —
  owns the inline-floor rule the block above follows
