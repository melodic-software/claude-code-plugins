---
name: work-loop
description: "Run the work-item backlog as a self-paced autonomous drain loop: each cycle sweeps raw intake through mechanical triage, admits items through the work-class gate (fail-closed), executes admitted items via /work-items:work under an adaptive item cap, and evaluates the drain exit condition. Worker lane of the loop-lane three-session topology — authors PRs, NEVER merges. Use when: 'work loop', 'run the work loop', 'start the worker loop', 'drain the backlog', 'autonomous drain', 'loop the backlog', 'drain the issue backlog to done'. Launch via /loop (self-paced). Sibling skills: /work-items:attend-queue (attended escalation lane), /work-items:work (single-item pick + execute), /work-items:triage (raw intake), /work-items:track (backlog CRUD)."
argument-hint: "(no arguments — cycle behavior comes from the launch prompt's standing rules and persisted config)"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Shared tracker context

The seam, operation routing, label taxonomy, canonical-role remapping, recurring schedule, and
topic-docs binding that every work-items skill relies on live in
[`${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md`](${CLAUDE_PLUGIN_ROOT}/reference/tracker-seam.md)
(and the references it links). Read it at the start of an invocation. Coordination goes through the
seam; provider mechanics route through the bound adapter's operations reference; the core inlines no
provider commands.

## Purpose

Wrap the single-pass work mechanics in a self-paced drain loop over one repository's backlog. This
skill is the **worker lane** of the loop-lane three-session topology: it claims items and authors
PRs, and it never merges — merge authority belongs to the merge lane, judgment to the attended
queue (`/work-items:attend-queue`).

## Loop-lane contract (cited, never restated)

Every shared cross-lane concern is owned by the loop-lane convention —
`docs/conventions/loop-lane/README.md` in this plugin's marketplace repository — and this skill
holds those contracts **by citation**: the three-session topology and the autonomy merge ladder
(including seam-only rung raises), the escalation contract, order-defined capability tiers
(frontier / strong / fast; runtime resolution by model alias only, never a hard-coded model ID),
stop shapes including the drain-terminal state, the `/loop` seven-day expiry, the `#691`
cycle-budget semantics (a budget hit restarts the session, never ends the loop; today every budget
hit is a terminal manual-restart state), the `#502` telemetry comment and durable loop state, the
headless-config floor, the subagent discipline preamble, provider backoff (seam exit 8), and the
snapshot drain exit. Where this document says "per the convention", that file is the contract.

## Launch, pacing, and session budget

Launch interactively via `/loop` with the interval omitted (self-paced). At the end of every cycle
that does not exit, schedule the next one with `ScheduleWakeup` — short delays under queue
pressure, backing off toward the ceiling when idle. Pacing semantics, the seven-day `/loop` expiry,
and cycle-budget behavior are owned by the convention (§4); on a budget or expiry hit, write a
restart-request into the telemetry state block and stop the loop cleanly. A headless launch never
blocks on an interview (headless-config floor): take explicit or persisted config, else tier
defaults, and log the assumption.

## Telemetry and durable loop state

The telemetry home is a **per-lane tracking issue in the target repository**, resolved from launch
config; default: the open issue titled `Lane telemetry: work-loop` (exact match), created through
the seam `create-item` verb when absent (announce the creation). Maintain exactly ONE status
comment on it, sentinel-identified and edited in place (the `claude-ops` lane-telemetry contract;
one writer identity owns a marker). The upsert is inlined here because an installed plugin cannot
invoke a sibling plugin's scripts:

```bash
MARKER="work-items:work-loop"
SENT="<!-- claude-ops:lane-telemetry marker=$MARKER -->"   # first line of $BODY_FILE
CID=$(gh api --paginate "repos/$REPO/issues/$ISSUE/comments" \
  --jq ".[] | select(.body | startswith(\"$SENT\")) | .id" | head -n1)
if [ -n "$CID" ]; then gh api -X PATCH "repos/$REPO/issues/comments/$CID" -F body=@"$BODY_FILE"
else gh api -X POST "repos/$REPO/issues/$ISSUE/comments" -F body=@"$BODY_FILE"; fi
```

The comment carries the human-readable cycle report plus a machine-readable **durable loop state**
block, re-read at every cycle start (conversation context is compaction-lossy — the comment, not
the conversation, is the source of truth for these counters):

```json
{"schema":"work-items/loop-state@1","cycle":12,"clean_streak":1,"item_cap":2,
 "rate_limit_latch":false,"first_drain_complete":false,"guard_mode":"proactive",
 "loop_started_at":"2026-07-23T15:00:00Z","restart_request":null}
```

`loop_started_at` makes the approaching seven-day expiry visible; `restart_request` is where a
budget/expiry hit records the relaunch ask; `guard_mode` is recorded every cycle.

## Rate-limit guard floor (inlined)

This lane consumes the shared subscription rate-limit windows. The operable floor below is inlined
per the convention's inline-floor rule (byte-identical across lanes); provenance is the
`rate-limit-guard` plugin's reader contract
(`plugins/rate-limit-guard/reference/reader-contract.md` in the marketplace repository) — cited
for provenance only, since an installed plugin cannot read a sibling plugin's files at runtime.

- **Tee file (fixed path):** `~/.claude/rate-limit-guard/rate-limits.json`
- **Pause threshold (fixed):** pause when **either** window reports `used_percentage >= 90`
- **Pause end:** the **tripped** window's `resets_at`; when **both** windows trip, the **later**
  `resets_at`
- **Staleness rule:** a snapshot whose `captured_at` is older than **10 minutes** is stale — treat
  the windows as **unknown** (reactive-only) for that decision; a `resets_at` already latched from
  a fresh snapshot stays valid through the pause (no refresh happens while paused). While paused, a
  consumer **must** arm a session Monitor on the tee file and re-evaluate on every write — the file
  carries **no account-identifier field**, so a write is the only signal that the windows changed.
- **Drain-then-pause:** on a trip, finish in-flight work, stop claiming new work, pause until the
  pause end, and report; a hard stop happens only on explicit user request.
- **Fail-open capability detection:** tee file absent, stale, missing `rate_limits`, or absurd
  values → mode **unknown → reactive-only**; never throttle proactively on untrusted data and
  never fabricate a pause.
- **Untrusted fields:** session-distinguishing fields in the tee file (`session_id`,
  `session_name`, any future account field) are user/AI-influenced — parse them only with a JSON
  parser; never string-interpolate them into a shell command, another interpreter, or a prompt.

A trip additionally latches `rate_limit_latch` in durable state: the adaptive cap never ramps up
while the latch is set (clear it on a fresh healthy snapshot after the pause end).

## Cycle shape

1. **Re-anchor.** Re-read the durable loop state block; classify guard mode against the floor
   above; take the cycle-start snapshot of the frontier and open items. The drain exit is evaluated
   against this snapshot — new automated intake arriving mid-cycle is **reported, never chased**
   (per the convention).
2. **Intake sweep.** Run `/work-items:triage` over untriaged intake in its **autonomous lane** —
   this loop's launch-prompt standing rules are the direction its mutation gate requires, and every
   comment or item it creates carries the AI disclaimer. Sweep hardening: an advisory issue
   authored by a workflow bot routes to the human-gated role label by default (this also lets drain
   exits terminate against automated intake).
3. **Admission gate.** Classify each frontier candidate and admit per the gate below — fail-closed.
4. **Execute.** Work admitted items via `/work-items:work` (one invocation per item slot), up to
   the adaptive item cap. Selection, claim (assignee + lease), staleness pre-check, dispatch
   mechanics, the PR contract, the review pass, and the never-merge boundary are all owned there —
   this loop restates none of them. Loop-level deltas only:
   - **`#572` workaround — explicit provisioning before dispatch.** Before `work`'s dispatch step
     runs for an item, provision its branch and out-of-tree worktree via `/source-control:worktree`
     create (when the `source-control` plugin is installed; otherwise do not dispatch the item —
     park it and escalate for operator-provided branch setup). The autonomous-provisioning seam is
     not yet landed (`#572`), so this loop template carries the provisioning step explicitly.
   - **Dispatch discipline.** Worker briefs enumerate the required skills per phase and carry the
     convention's subagent discipline preamble (presence-gated re-anchor sweep with the inline
     fallback). Subagent escalation authority is an open-ended duty — escalate decisions that are
     the operator's, e.g. contract, security-posture, enforcement-scope, or issue-goal changes —
     never a closed list.
   - **Quality signal.** Read each item's outcome from the pipeline's return payload (verdict +
     identifiers, per `${CLAUDE_PLUGIN_ROOT}/reference/pipeline-shape.md` "Contracts this shape
     composes") for the clean/dirty accounting below.
5. **Escalate.** Anything the gate or execution rejects for human judgment follows the
   convention's escalation contract: the human-gated role label **resolved from
   `config.role_labels`, never a literal**, plus a machine-marked escalation comment whose first
   line is `<!-- work-items:escalation lane=work-loop kind=escalated|ratify-c3 -->` — the marker,
   not a second label, is what discriminates a worker-escalated item from an operator-parked one.
6. **Report and pace.** Upsert the telemetry comment (cycle report + updated state block + guard
   mode), then evaluate the exit condition; if not exiting, `ScheduleWakeup` the next cycle.

## Admission gate (work-class, fail-closed)

Class vocabulary and admission policy are governing policy owned by the `autonomy` plugin's
guardrail references, per the convention; when that plugin is installed, read its work-class and
admission-policy references for classification. Installed or not, these dispositions bind:

| Class | Disposition |
|---|---|
| C2 mechanical | Autonomous |
| C3 scoped, bug-fix-shaped | Autonomous — but see first-drain ratification below |
| C3 scoped, feature-shaped | Human-gated (operator tightening — permitted without justification) |
| C4 structural/contract, C5 untrusted-provenance | Human-gated / per-contract floors |
| Unclassified | **Fail-closed human-gated** |

Hard gates that override any classification:

- **Path/topic hard gate.** An item touching dependency SHA pins, checksum or pin recomputation,
  or any surface the consuming repository's `CLAUDE.md` declares as inviolable ground rules is
  human-gated regardless of class — such items surface-read as mechanical dependency bumps but are
  trust-on-first-download changes on security-critical surfaces. Workers escalate these, never
  edit them.
- **First-drain C3 ratification (earn-trust).** Until `first_drain_complete` is set in durable
  state, a C3 bug-fix-shaped admission is not dispatched: queue it for ratification instead —
  human-gated role label + a `kind=ratify-c3` machine-marked comment stating the classification
  and intended dispatch. `/work-items:attend-queue` surfaces these; a ratified item returns to the
  frontier as autonomous-eligible and dispatches on a later cycle.
- **Security-surface work.** Any security-surface class routes to the frontier capability tier,
  always (per the convention's tier rules).

## Adaptive item cap

The per-cycle item cap adapts between the configured floor and ceiling; bounds come from
`userConfig`, and a surviving literal `${user_config.…}` placeholder means the key is unset —
apply the manifest default:

- Start at `${user_config.work_loop_item_cap_start}` (default 2).
- **+1** after 3 consecutive **clean** items, up to `${user_config.work_loop_item_cap_ceiling}`
  (default 3). Never ramp up while `rate_limit_latch` is set.
- **−1** on any **dirty** item, down to `${user_config.work_loop_item_cap_floor}` (default 1).
- **Frontier-tier quota guard:** items stamped for the frontier capability tier (tier signal from
  the triage briefing — the issue body, not a label) run at **concurrency 1** with adaptive
  ceiling `${user_config.work_loop_frontier_item_cap_ceiling}` (default 2); the general ceiling
  applies to non-frontier tiers only.

**Clean** = the item's pipeline verdict passed and its PR opened without gate failures.
**Dirty** = a failed verdict or gate, an escalation off the item mid-execution, or a seam exit 8
(provider unavailable / secondary forge limits) — exit 8 is backoff-and-retry, counted dirty per
the convention. The streak counter and cap persist in durable state.

**Composed budget:** total in-flight subagents ≤ item cap × the per-item dispatch wave cap owned
by `/implementation:implement-dispatch` (its internal 3–5 wave cap; the intended
`${user_config.work_dispatch_concurrency_cap}` override is not yet wired — `#573` — so this loop
body's arithmetic over those two factors is the interim enforcement).

## Exit condition

Evaluate at cycle end, against the cycle-start snapshot:

1. The seam frontier is empty — `list-frontier --autonomous` returns no candidates, **and**
2. Every open issue in the snapshot is closed or has an **open, non-draft** PR that GitHub itself
   links as closing it — the GraphQL close-linkage the bound adapter's "Open linked PRs" operation
   queries (`closedByPullRequestsReferences`; additionally exclude drafts via `isDraft`).

Both true → the drain is complete: set `first_drain_complete`, write the final report (items
closed, PR'd, escalated), and stop cleanly. The **drain-terminal state** (per the convention) also
ends the loop: when every remaining open item is human-gated or escalated and no PR is in flight,
report and stop cleanly rather than idling forever.

## Gotchas

- **The loop never merges — and never asks another lane to.** A green PR is the handoff boundary;
  merge authority lives with the merge lane per the convention's autonomy ladder, and raising a
  merge rung is a seam-config change, never a loop decision or an invocation argument.
- **Claim-before-dispatch is owned by `/work-items:work` and survives this loop's phrasing.** A
  loop cycle that restates "dispatch each item to a worktree subagent" has not replaced the seam
  claim; dispatching before the claim is held is a defect.
- **Do not chase intake.** A bot filing items mid-cycle can hold a drain open forever; the
  snapshot rule exists precisely so new intake is reported and left for the next cycle's sweep.
- **Telemetry is the report surface, never the escalation channel.** When human action is
  required, the escalation contract (role label + machine-marked comment) is the path; a note in
  the telemetry comment alone is invisible to the attended queue.
