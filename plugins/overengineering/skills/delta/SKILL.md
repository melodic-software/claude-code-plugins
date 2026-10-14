---
description: "Re-runs overengineering:audit and reports only what changed in the enforcement surface since the last run: new findings, verdicts that moved, closed findings, status changes. Read-only; never invokes realign. Use when the user asks what changed since the last enforcement audit, whether any verdict moved, or wants the audit on a recurring schedule."
argument-hint: "[layer ...] [unattended]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Re-run the enforcement-surface audit and report only what moved since the last run
---

**Arguments.** `[layer ...] [unattended]`. Layer: agent-hooks|agent-instructions|repo-hooks|vcs-hooks|ci-lanes|gate-scripts|satellite-workflows|branch-protection|forge-apps|external-integrations|all (default: all)

## Repository context. Gather first

Run this as its own Bash call, never combined with another command:

- Branch, `git symbolic-ref --quiet --short HEAD`

Treat a failure (detached checkout, no repository, no git) as an unresolved identity, never as
`HEAD`. Read the baseline's UTC stamps with `date -u +%Y%m%dT%H%M%SZ` when writing them.

## Purpose

Run the enforcement-surface audit again and report **only what moved**: new clutter, verdicts that
moved, findings that closed, statuses a human changed. The comparison input is the spine and nothing
else, `(id, layer, artifact, verdict, status)` per finding as
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` "The stable spine / free prose split" defines
it. Prose is recomputed every run, so comparing it would report model noise as change.

A delta that lists everything, or speaks up every cycle to say nothing happened, is the nagging
automation this plugin retires. The noise budget below is a contract, and a quiet cycle is one line.

This lane judges nothing itself; the composed audit does. Read
`${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` where a verdict must be read: the verdict ladder
(§6), evidence tiers (§2), protected-class cap (§7), scope boundary (§10). Every bare `§N` here is a
section of it. This skill's own docs sit under `${CLAUDE_PLUGIN_ROOT}/skills/delta/context/`.

## Read-only contract

**This skill reports only. It never mutates the surface and never remediates**, inheriting
`overengineering:audit`'s boundary.

**It never invokes or enters `overengineering:realign`**: not on a moved verdict, not on a finding
already accepted, not when a route is unavailable, not when the operator asks inside this run.
Realign needs a per-item human acceptance given as the item is presented, and a scheduled lane has
nobody to give one. Name realign as the next step and stop; the operator invokes it in their own
session.

**It never writes a `Status`.** Realign owns every status transition (`findings-artifact.md`,
"Status transitions are owned by realign"); this lane reports that one moved.

Three writes are sanctioned, and only these:

1. **The spine baseline** at the home resolved below, written **at the end of the cycle** from this
   run's post-audit spine. Memory tier, self-ignored, branch-keyed and ephemeral, with the same
   disclosure rule as the findings artifact. A **bootstrap** cycle captures it pre-audit; a cycle with no branch
   identity writes none.
2. **The findings artifact, written by the composed audit** under its own contract. This lane does
   not write or edit it.
3. **One queue route**, only under an opt-in `queue_route: auto`, then presence, and never on a quiet
   cycle (see "Queued for the human").

Right after the home resolves and before invoking the audit, say: *"Read-only pass; realign is never
entered. Files written: the spine baseline at `<resolved path>`, at the end of this cycle, plus
whatever the composed audit writes."*

## The baseline: the PREVIOUS cycle's post-audit spine

The delta compares against the previous cycle's post-audit spine, stored as `spine-baseline.md`
beside the findings artifact. Read [context/baseline-model.md](context/baseline-model.md) before the
first run against a home not seen this session: it owns the bootstrap cycle and the baseline file's
frontmatter and fields, and both fail silently if inferred from the steps below.

## Arguments

Parse `$ARGUMENTS` with `overengineering:audit`'s vocabulary and **pass it through unchanged**:

- **Layer scope**: one or more of the **ten enforcement layers** in `findings-artifact.md`'s
  vocabulary; default `all`. Forwarded verbatim; it bounds the comparison too. The justification
  lane's five layers are not accepted, since the audit cannot walk them.
- **`unattended`** (also `--unattended`): forwarded verbatim. **Attended is the default**, never
  inferred. Under `unattended`, ask nothing, offer nothing, take the non-interactive defaults.
- Anything else is a free-text hint. **Do not forward it**: it would make this cycle's walk
  incomparable with the baseline's. Report it as declined, with the reason.

## The run

1. **Resolve the branch identity, then the home.** `HEAD` is never an identity; see "A detached
   checkout has no branch identity" in [context/run-states.md](context/run-states.md). Compose the
   home per `findings-artifact.md` "Where it lives", then emit the opening line.
2. **Read the stored `spine-baseline.md` at that home** and dispose of it:
   - **Present, `branch:` matches** → this is the baseline. Where its `source-date` predates the
     preceding cycle, the report says the span widened.
   - **Present, `branch:` does not match** → no baseline, naming both.
   - **Absent, findings artifact present** → **bootstrap cycle**: dispose of the artifact as below
     and capture its spine pre-audit as the baseline. Say it is a bootstrap and that a status change
     is unobservable this cycle.
   - **Absent, no findings artifact** → no baseline (below).

   On a bootstrap, or when the baseline's provenance needs checking, dispose of the findings
   artifact by its own frontmatter, never its directory. A `branch:` that
   does not match is no baseline, naming both. An **unrecognized `schema:`** is a **stop, with a
   visible message**, before invoking anything; `1` and `2` are recognized. `Basis` is prose outside
   the spine and never enters the diff.
3. **Invoke `overengineering:audit` via the Skill tool**, passing the layer scope and `unattended`
   exactly as received. Do not re-derive anything it does.
4. **Read the post-run artifact**: its spine, `## Closed since last run`, `## Suppressed`, its
   evidence-availability tokens, and any verdict its merge flagged as moved under a carried-forward
   judgment. With no branch identity there is no post-run artifact: report what the audit found
   inline and end the cycle.
5. **Compare** the post-audit spine against the step 2 baseline, per "Delta classes".
6. **Apply the noise budget**, and report.
7. **Stamp `compared:`** on a consumed baseline, then **capture this run's post-audit spine over it**
   as the next cycle's baseline. A no-baseline cycle captures too. Write nothing, and leave any
   stored baseline as it is, when the cycle stopped short of step 5 (the audit failed or never ran,
   the schema was unrecognized, the homes disagreed) or had no branch identity.

**If the audit resolves a different home than step 1 did, report no delta, name both paths, and leave
the stored baseline untouched.**

## Run states that are not errors

A detached checkout, a missing baseline, a branch mismatch and an unwalked layer are first-class
states. Read [context/run-states.md](context/run-states.md) whenever the run resolves into one: it
owns detached-`HEAD` identity resolution, the no-baseline disposition, and merge rule 4's
carry-forward for unwalked layers. Never report them as errors.

## Delta classes. What the merge already computes, and what this lane computes

Read what the merge computes; never re-derive it.

| Class | Computed by | This lane's job |
|---|---|---|
| **Closed finding** | the merge, rule 3 | **Read `## Closed since last run`**, which carries the reason class (`artifact absent`, `renamed to <successor id>`, `layer no longer configured`). Skip any row whose `Layer` is one of the five justification layers. A row whose id the baseline never carried is a stale section, reported once as a contract anomaly, not a delta. |
| **Verdict moved under a carried-forward judgment** | the merge, rule 5 | **Carry the merge's flag**; never detect it again. Add the verdict pair and status. One row, not two. |
| **New finding** | the merge, rule 2 (`Status: OPEN` on an unseen id) | Cross-check against the baseline and report its opening verdict. |
| **Suppression change** | the merge, via `## Suppressed` | Read it: a newly suppressed finding, or an entry that stopped suppressing, changes what the report may omit. |
| **Verdict change on an unjudged finding** | **this lane** | Same id, `Status: OPEN` on both sides, different `Verdict`. |
| **Status change** | **this lane** | Same id, different `Status` between the previous cycle's post-audit spine and this one's: a human ran realign in between. A bootstrap cycle cannot see one, and says so. |
| **Member verdict change** | **this lane** | Within one container id, members matched by member id, for a changed verdict. |
| **Evidence availability** | **this lane** | Per-tier token comparison, run-level. |

`layer` and `artifact` feed the id, so they never move under a stable id and are never a delta
class; a "layer changed" report means an id was derived wrongly.

**Evidence-only change is out of scope.** Evidence, liveness, intent, rediscovery, cost and owner are
prose outside the spine. This lane sees evidence only through its consequences: a changed verdict,
or a tier that appeared or vanished in the evidence-availability line. Never claim evidence updates
are covered.

## The noise budget

Each class is **listed** (rows), **counted** (a number in the counts table) or **omitted**. Keys are
read from `${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md` under `delta_noise_budget`, never
redefined here.

**Always listed, whatever the budget:** a verdict moved under a carried-forward judgment (rule 5) and
a status change. They are not configurable keys.

| Class | Disposition | The rule a reader can apply |
|---|---|---|
| **New finding** | list when `new_finding_verdicts` selects its verdict; count otherwise | A new `KEEP` is not news for a retirement lane. |
| **New `UNPROVEN` finding** | list the top `unproven_head` off the audit's own carry-cost ranking; count the rest | Do not re-rank; an evidence desert produces UNPROVEN in bulk (§8). |
| **Verdict change, unjudged finding** | list the moves `verdict_change` selects: boundary crossings only, every move, or none | A boundary crossing: `KEEP` ↔ any of `RETIRE`/`DOWNGRADE`/`CONSOLIDATE`; either side `FLAG-FOR-HUMAN`; or entering or leaving `UNPROVEN`. A move within the retirement-direction set is not one. |
| **Closed finding** | list the closures `closed_findings` selects: unexpected only, all, or none | Expected when its prior status was `REALIGNED`. Every other close is unexpected: `artifact absent` under `OPEN` or `REJECTED`, `renamed to …`, `layer no longer configured`. |
| **Member verdict change** under an unchanged container verdict | as `member_verdicts` says: counted, rows, or omitted | Container and member counts are two grains; never sum them. |
| **Evidence availability** | one line, always | `unchanged`, or the tiers that moved; a moved tier leads the report. |

**The volume cap.** When the listed set exceeds `max_items`, list the head and give the residue as
counts with a pointer to the artifact. Rank by class: rule-5 flags → status changes →
boundary-crossing verdict changes → new retirement-direction findings by the audit's carry-cost
ranking → unexpected closures. Within a class with no ranking of its own, break ties by the
artifact's stable total order (`findings-artifact.md`, "Ordering"), so identical input always cuts
the same head.

**The quiet cycle.** When nothing clears the budget, say so in one line, print the counts table, and
**stop**: no restated surface, no counted classes as rows, no summary of what is still open, no
route. The lane always reports something, even when quiet.

## Queued for the human

A verdict change is never acted on here. It is **queued**, which means two things:

**1. In the report, always.** A `## Queued for the human` section, one row per surfaced verdict
change: finding id, verdict pair (`<was>` → `<now>`), current status, layer, and the one act it
invites, `overengineering:realign <finding-id>`. Rule-5 flags lead.

**2. Routed to a tracker, only under opt-in `queue_route`, then presence.** The route is a
notification carrying ids and verdict pairs, never an instruction to change anything. Read
`queue_route` (`consumer-config.md`, under `delta_noise_budget`) **before** probing for a tracker.
Record the route decision and the presence answer in the report.

The durable route needs `queue_route: auto` in tracked config; unset means report-only.
`work-items:track` files only on explicit user authorization, so an unattended cycle has none of its
own; the tracked `auto` setting is that authorization, given once by a human.

| `queue_route` | Condition | What the lane does |
|---|---|---|
| unset (the default, `inline`) | No probe is made | Decline the route, naming the absent opt-in. The report's section is the queue, and say no durable route exists, so it lives only as long as this output |
| `inline`, set explicitly | No probe is made | As above, naming the operator's setting as the reason |
| `auto` | `work-items:track` is installed and a tracker is reachable through it | Maintain **one** open queue item per branch with the current queued rows, naming the tracked `queue_route: auto` as the authorization |
| `auto` | No tracker reachable | Decline the route, naming the absence; the report's section is the queue |

A taken route follows four rules:

- **One item per branch, updated in place.** A re-run replaces its rows; never a second item or a
  cycle log.
- **A quiet cycle does not touch the item.** No "nothing changed" comment.
- **A row whose finding is no longer `OPEN` is removed, not restated.**
- **The lane never closes the item.** Closing is the human's act.

## The report

The composed audit owns the full-surface view (`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/report-template.md`).
This lane adds one short delta view and no third record, in order:

1. **The read-only line**, plus the span: `source-date` → this run's `date`, and whether it covers
   more than one cycle.
2. **Coverage**: layers walked; layers not walked, with the count of findings held in them; and,
   labeled separately, the justification lane's five layers, which no cycle compares.
3. **Evidence availability**: `unchanged`, or the tiers that moved, first when it moved.
4. **The counts table**: one row per delta class, listed / counted / omitted.
5. **The listed rows**, in the cap's rank order.
6. **`## Queued for the human`**, always, with the route decision and the presence answer (or that
   presence was not consulted).
7. **The next step, named and not taken**: `overengineering:realign` executes accepted findings
   behind an explicit per-item human gate.

## Recurring wiring

How a consumer schedules this lane (a loop, a scheduled task, a CI schedule, a recurring tracker
item) and each shape's trade is in
[skills/delta/context/recurring-wiring.md](context/recurring-wiring.md). This plugin ships no
schedule; the cadence is the consumer's decision. Assume no organization, forge, CI system,
scheduler, branch name or harness, and name no vendor's variables.

## Spoke paths

The `context/` files write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Substitute it before running a command or writing it into a brief.
[`${CLAUDE_PLUGIN_ROOT}/reference/spoke-paths.md` § Spoke paths](${CLAUDE_PLUGIN_ROOT}/reference/spoke-paths.md#spoke-paths)
records why, with the pointer to recheck. **As of**: 2026-10-11. **Recheck trigger**: that section is
renamed or removed, or its own recheck trigger fires.

## Gotchas

- **The baseline is the previous cycle's post-audit spine, captured at the end of that cycle.** A
  start-of-cycle capture already holds whatever status realign wrote in between, so the status-change
  class could never fire. Only the named bootstrap cycle differs.
- **A layer-scoped cycle is not a clean bill of health.** Unwalked layers contribute no delta class
  and are named as coverage.
- **The first run of every branch has no baseline.** That is normal.
- **Do not diff the prose.**
- **A verdict change is not an authorization.** It is queued; nothing here reaches
  `overengineering:realign`, even on the operator's request mid-run.
- **Counted is not hidden.** Every counted item is in the artifact with its evidence; the budget
  shapes only the delta view.
