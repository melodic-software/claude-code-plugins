# Loop-lane convention

Owner doc for the concerns shared by every **loop lane** — a session that wraps a single-pass
mechanic in a self-paced drain loop over a repository's backlog. Three lanes adopt it: the
`work-items` `work-loop` and `attend-queue` skills and the `source-control` `babysit-loop` skill.
Because those live in two different plugins, the topology, escalation contract, capability-tier
vocabulary, and loop-layer invariants they share cannot live inside either plugin — a
sibling-plugin file import is a defect
([`PLUGIN-PHILOSOPHY.md`](../../PLUGIN-PHILOSOPHY.md#design-boundary)), and a cross-plugin convention
lands in an owner doc before the second plugin adopts it
([convention registry](../../PLUGIN-PHILOSOPHY.md#convention-registry)). This is that owner doc.

**Pointer-not-copy.** Each mechanic below is owned by a plugin or a sibling convention; this doc
fixes the *contract* every lane holds to and points at the owner for the *mechanism*. It never
restates a mechanics block. The `autonomy` plugin remains the governing-policy pointer (the
guardrail matrix), and the loop lanes are the interim executor for the not-yet-built autonomy runner
([`runner.md`](../../../plugins/autonomy/reference/runner.md)); this convention is the loop-layer
contract that operates within that policy.

## 1. Three-session topology

A drained repository runs three cooperating sessions, each with exactly one authority:

| Session | Authority | Never does |
|---|---|---|
| Worker loop (`work-loop`) | Claims items, authors PRs | Merges |
| Babysit lane (`babysit-loop`) | Advances and merges PRs within the matrix's merge-policy column | Decides operator-owned questions |
| Attended queue (`attend-queue`) | Human-in-the-loop triage and escalation answers | Runs unattended |

The worker loop is PR-only; merge authority belongs to the babysit lane; judgment belongs to the
attended queue. No lane crosses into another's authority.

### Autonomy ladder (merge authority)

Merge authority is a configurable ladder with the safest rung shipped by default: **human merge for
every PR except gate-proven C2-mechanical ones**. The exception is a *work-class* test, not an
authorship test — a PR qualifies only when the item classifies C2 (mechanical), whether a bot, a
human, or a worker authored it; bot authorship alone is never sufficient. C3 and unclassified items
stay human-gated regardless of author, by default. **C4 (structural) and C5 (untrusted-provenance)
stay human-gated unconditionally — no rung, no seam config, and no invocation argument ever reaches
them**, per the autonomy matrix's own promotion contract: "never promotes — human merge always; no
evidence predicate exists for these cells"
([`work-classes.md`](../../../plugins/autonomy/reference/guardrails/work-classes.md#suggested-default-predicates)).
Higher rungs — up to full autonomy, where frontier-tier subagents resolve conflicts, answer review
comments, and drive a PR to merge — are opt-in per repository, and are bounded by that C4/C5 floor
regardless of rung name.

This shipped default is itself the recorded baseline rung, versioned in this convention and in the
tracked seam config. A repository adopts it through its own reviewable lane-enabling change — the
binding/config PR that turns a lane on in that repo — which is the recorded, human-ratified act for
the baseline rung, so no lane ever auto-merges without a reviewed change having enabled it. Raising
any higher rung — including any C3-autonomous merge — is a config change on the tracked, layered
config seam ([config-cascade](../config-cascade/README.md)), which makes it
exactly the autonomy matrix's required **human-ratified knob flip recorded on the governance
surface**
([`work-classes.md`](../../../plugins/autonomy/reference/guardrails/work-classes.md#promotion-and-demotion)).
C3-autonomous merge is therefore reachable only through a recorded, reviewable flip, never by
default — the matrix's promotion contract honored by construction. Demotion stays automatic and
fail-closed, per the same owner doc.

**Merge-rung raises are seam-only, with one named, explicit paired-argument exception.** Invocation
arguments never raise the merge rung *implicitly*: a raise binds only from the tracked seam config
layer, so every increase in the *standing* merge authority is the recorded, reviewable act above. An
argument may otherwise only select a *lower* (safer) rung for a single run, never a higher one.

The one exception: an invocation whose own argument line explicitly types **both** the literal
`autopilot` tier keyword **and** the dedicated raise argument `--merge c3-this-run` (each never
inherited, never defaulted, never supplied by a config layer, never composed by a model on the
caller's behalf) — in a repository that has already adopted the baseline rung above — widens that
single run's merge authority to cover every work class up to and including C3, still short of the
unconditional C4/C5 floor. The pair is deliberate: `autopilot` predates the exception as a
merge-inert tier keyword, so a saved invocation, alias, or expanded template that already carries
it must acquire no merge authority — the tier keyword alone leaves the merge rung at the seam
value. `c3-this-run` exists for this exception alone, so its presence is never a leftover; it is
not a rung name and is invalid in seam config. This is a **per-invocation, single-run widening**,
not a standing rung change: it persists nothing to config, ratifies nothing on the governance
surface, and reverts the moment a launched invocation omits either token. It is not a substitute
for the recorded C3-autonomous flip above — a repository wanting *standing* C3 autonomy still needs
that seam config change; this exception only ever covers the one invocation that named it.

**A safer argument still wins.** The exception lifts only the *raise* restriction, and the raise is
mutually exclusive with a safer cap by grammar: every merge-dimension argument value other than
`c3-this-run` only ever selects a lower rung, so an invocation naming `autopilot` and an explicit
`human-only` merge rung merges nothing — the resolution order is tracked rung, then the paired
raise, then the C4/C5 ceiling.

**The C4/C5 floor tests the PR, not the item's stamp.** `work-classes.md` assigns a class from the
risk-property bundle, "not the task's surface description", so a lane implementing the floor derives
both from the pull request before comparing any recorded class to the rung. C5 follows the code's
provenance — a cross-repository head, or an author the provider does not attest as an owner or
member of the base repository (an outside collaborator pushing a base-repository branch is external
despite a same-repository head; a missing or unreadable signal fails closed to C5) — which
"dominates every other property", so a fork PR closing an internally classified C2/C3 item is still
outside the exception; a repository-owner allowlist is not a trusted-author list and never stands in
for that test. C4 follows the diff's blast radius: a refactor, migration, or contract change is C4
however its item is stamped, and a PR whose shape no longer matches its recorded class fails closed
to escalation. The floor's verdict attaches to the exact head SHA it examined: any push after the
verdict — the pre-escalation resolver's or the merge-capable worker's own fix alike — re-derives
the verdict on the new head before any merge, so no head merges that the floor never examined.

Every PR this exception reaches that is blocked on a **machine-escalated** `needs-human` item, a
contradictory or security-relevant **machine-authored** review thread, or an open finding gets a
**fresh frontier-tier subagent** dispatched to resolve the blocker — sharing no context with
whatever produced the PR (§3), and holding the PR's own worker lease for the duration — before the
deterministic merge gate runs; the gate itself is never bypassed or weakened by this exception, only
the human-ratification step ahead of it is replaced by an independent agent's resolution for this
single run. The tier is resolved through §3's capability-tier binding, never a family alias fixed in
a lane.

**What the dispatch never reaches.** Human blocking feedback — a `CHANGES_REQUESTED` review,
explicit human blocking language, an unresolved inline human thread — remains a stop-and-ask
condition that escalates and is never resolved past; this exception does not amend a lane's own
human-feedback contract. Nor does it reach an **operator-parked** item: §2's role label marks parked
and machine-escalated items alike, and only the machine marker separates them, so an item without
that marker stays the attended queue's and draws no dispatch. Merge conflicts route to a lane's
dedicated conflict-resolution path and integrate merge-only; this exception never authorizes
rebasing a PR branch, which would need a force-push the lanes forbid.

## 2. Escalation contract

A lane escalates by creating or labeling a tracker item that carries the **`needs-human` role
label**, resolved through the consumer's `.work-item-tracker.json` `config.role_labels` map and
never compared as a string literal
([`label-taxonomy.md`](../../../plugins/work-items/reference/label-taxonomy.md#canonical-roles) owns
the canonical roles and the resolution). A machine-marked bot comment discriminates a
worker-*escalated* item from an operator-*parked* one — both wear the same role label, so the marker,
not a second label, carries the distinction. No lane creates labels; the label set is IaC-owned.

The event classes that oblige escalation are governing policy owned by
[`guardrails.md`](../../../plugins/autonomy/reference/guardrails.md#escalation) (gate failure,
verification divergence, admission rejection, demotion, structural-plan approval, and
untrusted-provenance). This convention adds no second escalation channel; the telemetry comment (§4)
is the report surface, never the sole path when human action is required.

## 3. Capability tiers

Model selection is expressed as **capability tiers defined by order, never by family name** —
capability does not track family across generations (a current mid-tier model can equal a prior
top-tier one), so a tier named for a family silently rots. Three ordered tiers:

| Tier | Role |
|---|---|
| frontier | Complex-stamped items; every security-surface work class, always |
| strong | Default implementer / worker |
| fast | Orchestrator and mechanical items; never weaker than the implementer it reviews |

Fixed rules: an advisor or reviewer is **at least as capable** as the main model it checks (equal
pairings are valid, and a fast orchestrator paired with an advisor at or above the main tier is the
recommended shape); a reviewer or verifier is never weaker than the implementer; a security-surface
work class routes to the frontier tier unconditionally.

**Independence, where a dispatch stands in for human ratification.** The one dispatch that resolves
a blocker in place of a human decision — the explicit-`autopilot` merge-authority exception (above)
— additionally requires the frontier-tier subagent to be a **fresh context sharing no conversation
history with whatever produced or previously reviewed the PR**: not a continuation of the PR-authoring
session, and not the same subagent instance that already replied on the thread being resolved. A
same-context or self-continuation dispatch does not satisfy this requirement even at the frontier
tier — the point of the tier is capability, the point of this rule is that the resolution is a
genuinely independent second opinion, not the original author or reviewer re-affirming itself.

**Runtime resolution is by model alias only.** The bare family-word aliases
(`fable` / `opus` / `sonnet` / `haiku`) are the live-updating handles that resolve to the current
recommended model for the provider and update over time; a dated model name is a pinned snapshot and
is never written into a lane body. Aliases are the only handle guaranteed under subscription OAuth,
so they are the runtime path; the Models API list endpoint is the **build/audit-time** verification
path, since it may require an API key a loop session lacks. No lane hard-codes a model ID. (Alias
semantics verified against <https://code.claude.com/docs/en/model-config> on 2026-07-23.)

Tier tables are built from a live official-docs fetch at authoring time, never from recall. Any new
model release re-audits the tier table — the trigger is recorded in this convention's
[`CHANGELOG.md`](CHANGELOG.md).

### Rate-limit windows

Subscription (Pro/Max) usage is bounded by a rolling five-hour window and a weekly cap. The weekly
cap's exact model scoping and numeric limits are volatile and are **not** restated here — see the
official [Anthropic support article](https://support.claude.com/en/articles/11049741-what-is-the-max-plan)
(verified 2026-07-23). The operable pause floor lives in the rate-limit guard binding (§6).

## 4. Loop-layer invariants

Every loop lane holds these, whatever single-pass mechanic it wraps.

**Stop shapes.** A lane runs in one of two shapes: *standing* (idle backs off toward longer wakeups;
no activity-timeout stop) or *drain* (stops when its backlog is empty). Drain carries a **terminal
state**: when every remaining open item is human-gated or escalated and no PR is in flight, the lane
reports and stops cleanly rather than idling forever — without it, an overnight drain deadlocks on
the first unanswered escalation.

A standing lane is additionally bounded by the `/loop` launch surface's **seven-day expiry**: a
self-paced `/loop` ends automatically seven days after it starts, idle backoff notwithstanding
(<https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry>, verified 2026-07-23). A standing
lane therefore requires a relaunch owner — today always the operator, for whom `claude-ops` `lanes`
`restart` is a one-command path (operator-initiated by contract; see the cycle-budget paragraph
below). The lane records its loop-started timestamp in the
lane's #502 telemetry block so the approaching expiry is visible ahead of time, and an expiry hit is
handled exactly like the cycle-budget hit below: a restart-request into the #502 block, then a clean
stop.

**Self-pacing.** A lane paces itself through `/loop` with the interval omitted; Claude schedules the
next iteration with `ScheduleWakeup`, whose delay is clamped between one minute and one hour.
`ScheduleWakeup` is called at the end of each iteration and is not operator-callable (verified
against <https://code.claude.com/docs/en/tools-reference> and
<https://code.claude.com/docs/en/scheduled-tasks> on 2026-07-23). Idle raises the delay toward the
ceiling. The `source-control` babysit lane's own self-pacing section
([`babysit-prs` loop reference](../../../plugins/source-control/skills/babysit-prs/reference/loop.md))
is the worked precedent.

**Cycle budget (#691).** A per-session cycle budget bounds one session; a budget hit **always**
emits a restart-request into the #502 telemetry block and stops the loop cleanly — a running loop
cannot `/clear` or relaunch itself, since a relaunch is the only context reset a lane gets
([`claude-ops` lanes](../../../plugins/claude-ops/skills/lanes/SKILL.md), section "A relaunch is the
only context reset a loop lane gets"). What happens next is launcher-relative. Under a launcher that
acts on restart-requests, the lane is relaunched and the loop continues — the budget restarts the
**session**, never ends the **loop**. **No such automatic launcher exists today**: `claude-ops`
`lanes` is operator-initiated by contract ("no scheduler runs `restart` for you today", per its
SKILL.md), so until an automatic relaunch trigger exists, *every* budget hit — under `lanes` or a
bare interactive `/loop` alike — is a **terminal** manual-restart state: the stop is reported in
lane telemetry, and the operator owns the restart (`lanes` `restart` is the operator's one-command
path). The restart-request in the #502 block is written so that the operator today, and an
automatic trigger when one exists, can act on the same surface.

**Telemetry comment (#502).** Each lane maintains exactly **one** status comment on a tracking item,
identified by a machine sentinel marker and **edited in place** every cycle — never a second comment.
`claude-ops`'s `telemetry-upsert.sh` is the interim home of this contract and a compatible reader
(`morning-brief` reads the same surface); an installed plugin cannot invoke a sibling plugin's
script, so each lane **inlines** the small `gh api` upsert and the coupling to `claude-ops` stays
one-directional.

**Durable loop state.** Conversation context is lossy across compaction, so a lane persists its
adaptive-cap streak counter, its rate-limit-warning latch, and its cycle count in a machine-readable
block of that same #502 telemetry comment, and re-reads them at each cycle start.

**Headless-config floor.** A headless lane launch never blocks on an interview: it takes explicit or
persisted config, or tier defaults, and logs the assumption. The interactive path may run a
mini-interview and offer to persist the answer; the headless path never waits on one.

**Provider backoff (seam exit 8).** A tracker-seam exit 8 — provider unavailable, or secondary forge
limits under one credential — is handled as backoff-and-retry and counted as a **dirty** signal for
the adaptive cap.

**Snapshot drain exit.** The drain-exit condition is evaluated against a snapshot taken at cycle
start; new automated intake arriving mid-cycle is **reported, never chased**, so an item-producing
bot cannot hold a drain open indefinitely.

**Subagent discipline preamble.** Every subagent a lane dispatches carries a standing discipline
preamble. When the `discipline` plugin is installed, the dispatch prompt invokes its sweep —
sweep-all, use-your-skills, do-your-research; when it is absent, the dispatch prompt
inlines the equivalent standing instructions (verify claims against authoritative sources before
acting, prefer installed skills over ad-hoc approaches, and re-check work against the active
conventions). The reference is presence-gated with this inline fallback per the
[seam-phrasing convention](../seam-phrasing/README.md) — `discipline` is never a hard dependency.

## 5. Consumers and launch surfaces

| Consumer | Plugin | Lane |
|---|---|---|
| `work-loop` | `work-items` | worker (PR-authoring drain) |
| `attend-queue` | `work-items` | attended triage / escalation queue |
| `babysit-loop` | `source-control` | merge lane over [`babysit-prs`](../../../plugins/source-control/skills/babysit-prs/SKILL.md) |

All three adopters have shipped. This owner doc landed ahead of them, per the convention-registry
rule; the table above is a live consumer list, not a forward reference.

**Launch surfaces.** A lane launches interactively via `/loop` — the primary surface, built-in and
dependency-free — or headless via the `claude-ops` `lanes` launcher, which stores the one-line lane
prompt through its `prompt_dir` seam (#480). `lanes` is a **supporting, strictly one-directional**
launcher: it launches the lane; no lane body ever requires, imports, or degrades without
`claude-ops`. Every mention of `lanes` in a lane body is presence-gated with the `/loop` fallback
documented at the site, per the [seam-phrasing convention](../seam-phrasing/README.md).

## 6. Rate-limit guard binding

All three lanes consume the shared subscription rate-limit windows (§3). An installed plugin cannot
read a sibling plugin's files or this repo's `docs/` at runtime, so each consuming lane body
**inlines the operable floor** — the fixed tee-file path, the 90%-of-either-window pause threshold,
the staleness rule, and drain-then-pause — and cites the guard's reader contract for provenance only.
That reader contract is
[`plugins/rate-limit-guard/reference/reader-contract.md`](../../../plugins/rate-limit-guard/reference/reader-contract.md),
shipped with the `rate-limit-guard` plugin. This convention records the inline-floor rule so the
values stay byte-identical across lanes; fleet audits check conformance per consumer.

**Single-account-per-machine is a known gap, not a safe assumption.** The tee file is
last-writer-wins and carries no account identifier, so a machine running lanes under more than one
account feeds one account's healthy windows to lanes running on the exhausted one, and the guard
cannot detect it. Same-machine account rotation is real operating practice, not a hypothetical.

This is recorded as a **gap** rather than as an invariant because the previous framing — "operation
assumes one account per machine" — was descriptive of how the guard happened to be built rather
than normative, and it fail-**opened** in a contract that fail-closes on every other unresolvable
input. It also baked a solo-operator posture into a contract whose sibling states that it "assumes
no machine, org size, or budget"
([`routines.md`](../../../plugins/autonomy/reference/routines.md) §Hosting stance) — a
multi-account machine is an ordinary team and multi-tenant shape, not an exotic one. Naming it a
gap changes no lane's obligations today; it removes the false assurance that nothing is missing.

**The resolution is account identity, and it is designed elsewhere.** `TODO(#1218)` owns the
design across all three sides — a writer-side identity field in the tee shape, reader-side
invalidation of latched state on identity change, and the re-audit of every lane body's inlined
guard floor that a floor change obliges. This section is deliberately not the place that decides
them: it records the gap and defers, so that when the design lands it replaces a stated gap rather
than contradicting a stated invariant.

**Guard-mode telemetry.** Each lane records the guard's mode — proactive, reactive, or unknown — in
its #502 telemetry block every cycle, so a silent degradation to reactive-only stays visible on the
tracking surface.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). A change to the topology, the
escalation contract, the tier vocabulary, or any loop-layer invariant is a major bump; additive
guidance is a minor bump.

**Recheck triggers** ([upstream-drift](../upstream-drift/README.md) owns the stamp-and-trigger
discipline: a dated verification stamp here is an as-of record, never standing authority). Two, and
every one of them is recorded as a changelog entry:

- Any new model release re-audits the capability-tier table (§3).
- Any change to this convention, or to a consuming lane, that RELIES on an upstream-sourced claim
  re-verifies that claim against its cited page first and refreshes the claim's verification date
  with the outcome.

The upstream surfaces these claims rest on — the `/loop` seven-day expiry, the `ScheduleWakeup`
bounds, model-alias semantics, the rate-limit windows — move on a research-preview cadence. Where
re-verification finds drift, the changed value lands here as a recorded entry rather than silently
inside a lane body.
