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
The same step that files the escalation writes the local escalation record (below), the
deterministic surface for out-of-band notification.

The event classes that oblige escalation are governing policy owned by
[`guardrails.md`](../../../plugins/autonomy/reference/guardrails.md#escalation) (gate failure,
verification divergence, admission rejection, demotion, structural-plan approval, and
untrusted-provenance). This convention adds no second escalation channel; the telemetry comment (§4)
is the report surface, never the sole path when human action is required. The escalation record
write and the out-of-band notification seam below are notification depth on the one filed
escalation — the fan-out posture the runner design
([`escalation.md`](../../../plugins/autonomy/reference/runner/escalation.md)) names — never a
second channel: the tracker item remains the single escalation of record.

### Escalation record write

Every escalation an autonomous lane files (`work-loop`, `babysit-loop`; the attended queue answers
escalations, it does not file them) also writes a local **escalation record** in the same step that
files the tracker item, **immediately before** it posts the marker comment: a new JSON file created
with the **Write tool** at
`.claude/lane-escalations/<UTC-stamp>-<item>-<lane>.json` in the session's checkout — stamp
`YYYYMMDDTHHMMSSZ`, `<item>` the tracker item number (e.g.
`20260726T031500Z-1234-work-loop.json`). The record carries the machine-readable shape of the
escalation the tracker item already holds:

```json
{"schema":"loop-lane/escalation-record@1","lane":"work-loop","kind":"escalated",
 "repo":"<owner>/<repo>","item":"<tracker item URL>",
 "summary":"<the marker comment's one-line question>","written_at":"<UTC ISO-8601>"}
```

`kind` mirrors the marker comment's `kind` token. The write is signal, not storage: no lane reads
the record back, and the tracker item stays the escalation of record.

**Ignoring the record directory is the lane's own preflight, not a consumer obligation.** Because
the write is unconditional, an unignored directory strands an untracked file in the working tree a
lane runs its gates against, and escalation detail sits one careless stage from being committed.
Nothing delivers a tracked ignore rule into a consuming repo — this marketplace's root rule covers
only its own dogfooding checkout, and a plugin ships no consumer-side `.gitignore` — so a lane that
depended on the consumer having added one would break for every existing consumer that upgrades
without noticing. Each lane therefore closes this itself, once at lane start, before any cycle runs:
if `git check-ignore -q .claude/lane-escalations/` reports the path unignored, append
`/.claude/lane-escalations/` to `$(git rev-parse --git-common-dir)/info/exclude`. That file is
per-clone and untracked, shared across the clone's worktrees, so the repair needs no consumer
change, alters no tracked file, and cannot itself dirty the tree. A consuming repo may still add the
rule to its tracked `.gitignore` through its lane-enabling adoption change — the durable form,
carried to every clone — and the preflight then finds the path already ignored and does nothing.
Three rules make the signal deterministic:

- **Write tool, never a shell redirect.** Only a `Write` tool call emits the `PostToolUse` event
  the seam below keys on; a shell redirect writes the same bytes but emits only a `Bash` tool
  event, which the seam's `Write` matcher never sees.
- **One record per newly filed escalation.** What suppresses a duplicate is the read the lane
  already performs before escalating: an item that already carries its marker for this kind — a
  still-unratified `ratify-c3`, an idempotent label re-convergence — is not a new escalation, so
  the cycle files no second comment and writes no second record. Within that rule the
  `<UTC-stamp>-<item>` filename is unique, so each newly filed escalation is a fresh `Write`
  (never an `Edit`) producing exactly one hook event.
- **Record first, marker second — the failure direction is chosen.** The two writes are not
  atomic, and a lane can stop between them. Written in this order, a stop after the record leaves
  an escalation with no tracker comment; the next cycle reads no marker, re-escalates, and writes a
  second record — a duplicate notification, recoverable by the human who receives it. The reverse
  order fails the other way and cannot be recovered: a stop after the marker post leaves the marker
  standing with no record ever written, and that standing marker suppresses the record on every
  later cycle, so the out-of-band notification for that escalation is lost permanently. Ordering is
  what makes the seam fail loud rather than silent; no reconciliation pass is needed, and none
  would be reliable, since a compensating write can stop in exactly the same window.

The `summary` restates the marker comment's one-line question — text the lane already published on
the tracker — so the record itself adds no new secret surface. The hook payload the seam sends is
larger than the record; see the egress note below.

### Out-of-band notification seam

The local channels (OS toast, terminal bell/OSC 9 — the `autonomy` plugin's `lane-notify.sh`)
reach only an operator at the machine running the lane. The escalation record write gives a
consuming repo a deterministic surface that reaches one who is not: a `PostToolUse` hook in the
consuming repo's own tracked `.claude/settings.json`, matched on the `Write` tool, filtered to the
record directory, with a `type: "http"` handler that POSTs the hook event's JSON —
`tool_input.content` carries the record — to the repo's chosen endpoint. Documented default shape:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "http",
            "url": "https://alerts.example.com/lane-escalations",
            "if": "Edit(/.claude/lane-escalations/**)",
            "headers": { "Authorization": "Bearer $LANE_ESCALATION_WEBHOOK_TOKEN" },
            "allowedEnvVars": ["LANE_ESCALATION_WEBHOOK_TOKEN"],
            "timeout": 30,
            "statusMessage": "Notifying escalation webhook..."
          }
        ]
      }
    ]
  }
}
```

Every element is a documented first-party mechanism (verified against
<https://code.claude.com/docs/en/hooks> and <https://code.claude.com/docs/en/permissions> on
2026-07-27):

- `type: "http"` handlers POST the hook's JSON input with `Content-Type: application/json` and are
  supported in project `.claude/settings.json` — and every other settings scope — on `PostToolUse`;
  the one documented handler-type restriction that excludes them is on `SessionStart`. The seam is
  therefore per-consuming-repo configuration; no plugin ships it. It is deterministic (the handler
  fires on the matched lifecycle event, no model judgment) and carries no claude.ai subscription or
  Remote Control dependency.
- The `if` field holds exactly one permission rule and is evaluated on `PostToolUse`. File rules
  use the `Edit(...)` form — Edit rules cover all file-editing tools, `Write` included, and a
  `Write(path)` rule is never matched — and the single leading `/` anchors at the settings source
  (`<project root>` for project settings). Each worktree checkout carries its own copy of the
  tracked settings file, so by that settings-source rule the one tracked rule anchors at each
  worktree's own root — an applied inference: the docs state worktree matching explicitly only
  for local-settings rules.
- Header values interpolate environment variables only for names listed in `allowedEnvVars`. The
  docs document interpolation for `headers` alone and say nothing about `url`, so treat the `url`
  field as non-interpolating — an applied inference, and the reason the endpoint URL is tracked
  config while the secret rides only in a header sourced from the operator's environment, never in
  the repo.
- **Egress note.** The POST body is the full `PostToolUse` hook input, not just the record:
  alongside `tool_input` (the record's path and content) it carries session metadata — for
  example `session_id`, `cwd`, and `transcript_path`, which are absolute local paths and project
  identity. Configuring the hook is the consuming repo's deliberate opt-in to that egress; point
  the URL only at an endpoint trusted with it.
- A non-2xx response or a connection failure is a non-blocking error: a dead endpoint never blocks
  a lane.

**Destination is the consumer's choice.** The URL is any HTTP endpoint the consuming repo
controls: a generic webhook receiver, an internal alerting service, or a relay that reshapes the
payload for a chat service (a Slack incoming webhook expects its own JSON shape and rejects the
raw hook payload, so Slack reach goes through a relay). Two non-deterministic layers may ride
alongside, never instead: the built-in `PushNotification` tool, and model-driven outbound send via
a chat plugin (UNVERIFIED here — confirm the plugin and its send capability against its own docs
before relying on it). `PushNotification` "sends a desktop notification, and a phone push when
Remote Control is connected"; it prompts for no permission, but the model decides when to call it.
Its phone leg therefore inherits Remote Control's documented requirements — a claude.ai Pro, Max,
Team, or Enterprise plan (API keys unsupported), a claude.ai login, a session talking directly to
the Anthropic API, and accepted workspace trust — and additionally needs the separately documented
mobile setup: the app installed and signed in on the same account, OS notifications allowed, and
push enabled in `/config` (verified 2026-07-27:
<https://code.claude.com/docs/en/tools-reference>, <https://code.claude.com/docs/en/remote-control>).
Only the http hook is the deterministic leg.

**The seam binds to the session's project, never to the repository a lane targets.** The record
path is relative to the session's checkout, and the hook that fires is the one in that session's
loaded project settings. So a lane whose scope argument names a repository other than its own
checkout — a supported merge-lane mode — POSTs to the *launching* project's endpoint, and the
target repository's tracked hook is never consulted. That is the seam as specified rather than a
misconfiguration: "the consuming repo" is whichever project the lane session runs in, which is also
the project whose settings the harness loaded. **Running the lane from the target repository's own
checkout is therefore a requirement, not a preference, whenever that repository's endpoint is the
one that must hear** — a lane launched from a neutral directory or another repository's checkout
notifies that project's endpoint or nobody, and no configuration in the target repository changes
it. Writing the record into the target repository's tree instead would be strictly worse, not a
fix: the seam's `if` rule anchors at its own settings source, so a record written outside the
session's project matches no loaded rule and fires no hook at all, trading a
notification-to-the-wrong-endpoint for silence. Note the asymmetry with
policy resolution, which deliberately reaches the target repository's tracked file over `gh api`:
that is a read a lane performs, while the hook is fired by the harness from loaded settings, which
no lane can redirect.

**Degradation.** A consuming repo with no hook configured loses only the out-of-band leg — the
tracker escalation and the local notify are unchanged, and the record files are inert exhaust. A
closed laptop or a dead process emits no hook event at all; the record write covers a lane that is
running but unattended, and lane-down detection stays with the stop gate and telemetry freshness
(§4).

**A configured hook can also fail silently.** An env-var name absent from `allowedEnvVars`
interpolates as an empty string (documented: "references to unlisted variables are replaced with
empty strings"); a listed name unset in the operator's environment has no value to supply and
plausibly interpolates the same way — an applied inference, not stated in the docs. Either way, a
non-2xx response or connection failure is a non-blocking error, so a misconfigured hook can 401 on
every escalation while the lane runs on with nothing surfaced outside debug logs. Verify the leg
when wiring it — write a throwaway record file with the Write tool and confirm the endpoint
received the POST — and treat webhook silence across cycles that filed escalations as a
check-the-hook signal, never as proof of health.

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

**Where independence stops is a decision, not an omission.** The fresh-context requirement above is
the *only* one this contract imposes, and there is deliberately **no** routine per-cycle independent
review of ordinary loop output. The rationale: independence is the substitute for a *human
decision*, and the ordinary path takes none. Its correctness rests on deterministic gates — the
merge gate, CI, the work-class admission test — which are unbiased by construction, so a reviewer
spending a frontier-tier dispatch every cycle would re-check machine-checkable facts and buy no
independence that is not already there. The one path that does carry the requirement is precisely
the one where no gate can decide and an agent's judgment stands in for a person's. A lane's conflict
path is not a second instance: it dispatches a fresh conflict *worker* to resolve, which is a
resolution role rather than a second opinion ratifying a decision a human would otherwise make. This
is the boundary's stated justification, so the boundary is revisited when that premise changes — a
path whose outcome stops being gate-decidable acquires the independence requirement, recorded as a
versioned entry in [`CHANGELOG.md`](CHANGELOG.md) rather than silently.

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
`/loop` ends automatically seven days after it starts, on either launch shape (§5) and idle backoff
notwithstanding (<https://code.claude.com/docs/en/scheduled-tasks#seven-day-expiry>, verified
2026-07-27, broadened from the 2026-07-23 stamp's self-paced-only wording). A standing lane
therefore requires a relaunch owner — today always the operator, for whom `claude-ops` `lanes`
`restart` is a one-command path (operator-initiated by contract; see the cycle-budget paragraph
below). The lane records its loop-started timestamp in the lane's #502 telemetry block so the
approaching expiry is visible ahead of time, and an expiry hit is handled exactly like the
cycle-budget hit below: a restart-request into the #502 block, then a clean stop.

**Self-pacing.** A lane paces itself through `/loop` with the interval omitted; Claude schedules the
next iteration with `ScheduleWakeup`, whose delay is clamped between one minute and one hour.
`ScheduleWakeup` is called at the end of each iteration and is not operator-callable (verified
against <https://code.claude.com/docs/en/tools-reference> and
<https://code.claude.com/docs/en/scheduled-tasks> on 2026-07-27, no drift from the prior
2026-07-23 stamp). Idle raises the delay toward the ceiling. The `source-control` babysit lane's own
self-pacing section
([`babysit-prs` loop reference](../../../plugins/source-control/skills/babysit-prs/reference/loop.md))
is the worked precedent.

**The prompt runs fresh; the session does not.** Each cycle re-sends the lane's prompt verbatim into
the **same** session, so "runs fresh every time" describes the prompt and never the context: a lane
prompt never assumes a fresh one, and what carries forward also degrades, since auto-compaction
summarizes earlier history in place rather than preserving it
([`claude-ops` lanes](../../../plugins/claude-ops/skills/lanes/SKILL.md#a-relaunch-is-the-only-context-reset-a-loop-lane-gets)
owns the mechanism).

**Cycle budget (#691).** A per-session cycle budget bounds one session; a budget hit **always**
emits a restart-request into the #502 telemetry block and stops the loop cleanly — a running loop
cannot `/clear` or relaunch itself, since a relaunch is the only context reset a lane gets
([`claude-ops` lanes](../../../plugins/claude-ops/skills/lanes/SKILL.md#a-relaunch-is-the-only-context-reset-a-loop-lane-gets)).
What happens next is launcher-relative. Under a launcher that
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
one-directional. An inlined upsert carries none of the wrapper's body checks, so it is bound by the
`@path`-as-body rule in [`claude-ops` lanes](../../../plugins/claude-ops/skills/lanes/SKILL.md),
section "Never pass a body as an `@path` string".

**Durable loop state.** Conversation context is lossy across compaction, so a lane persists its
adaptive-cap streak counter, its rate-limit-warning latch, its consecutive-no-progress counter, and
its cycle count in a machine-readable block of that same #502 telemetry comment, and re-reads them
at each cycle start.

**No-progress detector.** Every stall mechanism below the loop layer is per-PR or per-item, so a
lane cycling repeatedly while accomplishing nothing in aggregate is invisible to itself: each gate
correctly declines to spend a worker, and nothing notices the aggregate is zero. Each unattended
lane (worker, merge — the attended queue is exempt: its operator is present by definition)
therefore persists a consecutive-no-progress counter, `no_progress_streak`, beside its other
durable counters in the #502 state block (absent from a re-read block = 0). What counts as a
qualifying progress event is lane-specific and defined in each lane body; the semantics here are
shared. A cycle whose cycle-start snapshot held actionable work for the lane and that ended with no
qualifying progress increments the counter; an idle cycle — nothing actionable in view — leaves it
unchanged (idle is not stalled); any qualifying progress resets it to zero. A **held** cycle is a
third state and also leaves the counter unchanged: whenever the rate-limit guard (§6) bars the lane
from claiming new work, the lane declines mutating work *by design*, so however much sits in its
snapshot, no qualifying progress was available to make. The **bar** is what the hold keys on, never
the pause window alone — a lane whose inlined floor latches that suppression in durable state stays
barred after the pause ends, and a latch no fresh healthy snapshot ever clears would otherwise trip
the threshold by itself. Held is not stalled: guard suppression outlasting three cycles would
otherwise escalate a lane for obeying the guard exactly. Only cycles the lane was free to act in are
counted, so the detector measures a lane failing to move a queue it could have moved.
When an increment
brings the counter to the stall threshold — default **3** consecutive no-progress cycles; a lane
may expose the threshold on its own config surface — the lane **escalates and keeps looping**: a
stalled lane is usually a signal about the queue, not a reason to terminate. The stall escalation
rides §2's contract unchanged (role label + machine-marked comment) — a loop-health signal on the
one channel, not a second channel and not a new guardrail event class. At most one stall escalation
per lane is open at a time: before raising one, the lane checks for an existing open stall
escalation authored by its own write identity (author-matched — a third party's lookalike never
suppresses the signal) and raises nothing while one exists. The stall escalation itself is never a
qualifying progress event, so the detector cannot reset itself by escalating — and more generally,
a lane's own repeat attempt at the same still-unresolved blocker never qualifies either: the
detector measures the queue moving, not the lane retrying. When progress resumes while a stall
escalation is still open, the lane records the resumption as a comment on it and leaves the
disposition to the operator.

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

**Two launch shapes, selected per invocation — neither deprecates the other.** Supplying an interval
(`/loop 15m …`) converts it to a cron expression and fires on that fixed schedule, subject to
jitter; omitting it hands the delay to Claude, which picks one per iteration within the §4 bounds
and is not jittered. `ScheduleWakeup` reschedules a *self-paced* loop only, so it is not the pacing
mechanism once an interval is supplied
(<https://code.claude.com/docs/en/scheduled-tasks#let-claude-choose-the-interval>, verified
2026-07-27). The §4 seven-day expiry binds both shapes. Both are current; this note reconciles which
applies where and changes neither.

Jitter is the scheduler's deterministic offset on a *cron* task: up to 30 minutes after the
scheduled time, or up to half the interval for a task running more often than hourly.

- **A lane always omits the interval.** Two §4 invariants need the self-paced shape and neither
  survives a cron schedule. *Idle backoff* — the standing shape's "idle backs off toward longer
  wakeups" — derives the next delay from what the cycle just observed, which a fixed cadence cannot
  consume. And a self-paced loop can **end itself** — Claude calls `ScheduleWakeup` with
  `stop: true` — which is how the drain shape's terminal state stops a lane cleanly; a fixed-interval
  loop keeps running until stopped by hand or until the seven-day expiry, so a drain lane launched
  that way cannot honor its own stop condition
  (<https://code.claude.com/docs/en/scheduled-tasks#stop-a-loop>, verified 2026-07-27). Self-paced is
  the lane shape by construction, not by preference. Two of the lane's other per-cycle signals —
  the adaptive-cap streak, and seam exit 8 counted as dirty — govern *how much work a cycle takes
  on*, not when the next one fires, and are unaffected by either shape. The drain-exit snapshot is
  not one of them: it is the pacing signal named above, the input deciding whether the cycle calls
  `ScheduleWakeup` with `stop: true` instead of scheduling another run at all.
- **A fixed interval is the operator's shape for invoking a single-pass mechanic directly.** The
  interval chosen once *is* the whole cadence policy: no per-cycle state derives a better one, so
  there is nothing for the cron schedule to discard. `babysit-prs`'s documented
  `/loop 15m /source-control:babysit-prs worker` line is that shape.

The two shapes coexist inside one plugin without conflicting because they answer different
invocations, not competing defaults: `babysit-prs` documents a fixed-interval launch of *itself*,
while its cadence mapping
([`loop.md` §5.3](../../../plugins/source-control/skills/babysit-prs/reference/loop.md#53-self-pacing-schedulewakeup))
is the self-paced contract the `babysit-loop` lane consumes. Reading either as the other's default is
the confusion this note exists to prevent.

**Known gap — the self-paced shape is provider-conditional.** On Amazon Bedrock, Claude Platform on
AWS, Google Cloud's Agent Platform, and Microsoft Foundry, an omitted interval does **not** hand the
delay to Claude: the prompt runs on a fixed ten-minute schedule and `ScheduleWakeup` is unavailable
(<https://code.claude.com/docs/en/scheduled-tasks>,
<https://code.claude.com/docs/en/tools-reference>, verified 2026-07-27). A lane launched there keeps
the loop but loses both properties the bullet above depends on: idle backoff cannot lengthen the
wake, and the lane cannot end itself — so a **drain** lane there deadlocks on the first unanswered
escalation exactly as §4's terminal state exists to prevent, and runs until stopped by hand or until
the seven-day expiry. No lane detects the provider today, so this is recorded as a known gap rather
than left as an unstated assumption, on the model §6 uses for the single-account assumption.

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
discipline). Two. A firing that finds drift lands its outcome as a changelog entry; a no-drift
firing refreshes the claim's verification date in place — no entry, no bump:

- Any new model release re-audits the capability-tier table (§3).
- Any change to this convention, or to a consuming lane, that RELIES on an upstream-sourced claim
  re-verifies that claim against its cited page first and refreshes the claim's verification date
  with the outcome.

The upstream surfaces these claims rest on — the `/loop` seven-day expiry, the `ScheduleWakeup`
bounds, model-alias semantics, the rate-limit windows — move on a research-preview cadence. Where
re-verification finds drift, the changed value lands here as a recorded entry rather than silently
inside a lane body.
