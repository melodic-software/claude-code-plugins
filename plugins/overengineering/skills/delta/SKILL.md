---
description: "Report only what changed in the enforcement surface since the last audit. Captures the prior findings spine, re-runs `overengineering:audit` over it, and compares the two — new clutter, verdict moves, closures, status changes — filtered through a configurable noise budget, so a recurring run is a short delta instead of the whole surface again. Read-only always: it never invokes or enters `overengineering:realign`, never writes a Status, and never touches the surface it reads; verdict changes queue for the human. A first run establishes a baseline and reports no deltas. Use when: 'what changed since the last audit', 'delta since the last run', 'run the enforcement audit on a schedule', 'recurring overengineering check', 'only show me what is new', 'did any verdict move', 'weekly automation-cruft check'. Pass layers to scope the pass and `unattended` for a scheduled or dispatched run; both pass straight through to the audit."
argument-hint: "[layer ...] [unattended] — layer: agent-hooks|agent-instructions|repo-hooks|vcs-hooks|ci-lanes|gate-scripts|satellite-workflows|branch-protection|forge-apps|external-integrations|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Re-run the enforcement-surface audit and report only what moved since the last run
---

## Pre-computed context

- Branch: !`git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown (no checkout)"`

Deliberately one line. A precompute block carrying a git command **and** more than one injection line
is refused outright in a worktree-isolated agent, which is exactly the dispatched context a scheduled
run of this lane arrives in. The baseline's UTC stamps are read with an ordinary `date -u
+%Y%m%dT%H%M%SZ` call at the moment they are written, where they are accurate anyway.

## Purpose

Run the enforcement-surface audit again and report **only what moved**. A surface that has already
been audited does not need to be re-served every cycle; what an operator needs on the second and
every later run is the difference — new clutter, verdicts that moved, findings that closed, statuses
a human changed.

This is the recurring lane the findings artifact's stable spine was designed for. The comparison
input is the spine and nothing else: `(id, layer, artifact, verdict, status)` per finding, exactly
as `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` defines it under "The stable spine / free
prose split". Prose is recomputed fresh every run by construction, so comparing it would report
model noise as change.

**The failure this lane exists to avoid is its own.** A delta report that lists everything, or that
speaks up every cycle to say nothing happened, is the nagging automation this plugin exists to
retire. The noise budget below is therefore a contract, not a preference, and a quiet cycle is one
line.

The method is **not restated here.** Read `${CLAUDE_PLUGIN_ROOT}/context/scrutiny-method.md` where a
verdict has to be read rather than re-derived — the verdict ladder (§6) whose tokens the spine
carries, the evidence tiers (§2) whose availability frames every UNPROVEN row, the protected-class
cap (§7), and the scope boundary (§10). Every bare `§N` in this skill is a section of that one
document. This lane judges nothing on its own: it composes the audit, which does the judging.

**Two doc roots, different directories.** Shared docs sit at the plugin root
(`${CLAUDE_PLUGIN_ROOT}/context/…`, `${CLAUDE_PLUGIN_ROOT}/reference/…`); this skill's lane docs sit
under `${CLAUDE_PLUGIN_ROOT}/skills/delta/context/…` and are linked relatively below, with their
plugin-relative path as the link text — resolving one against the plugin root lands on nothing.

## Read-only contract

**This skill reports only. It never mutates the surface it reads, and it never remediates.** No hook
is disabled, no workflow edited, no gate script deleted, no setting changed, no branch rule touched.
It inherits that boundary from `overengineering:audit`, which it composes, and adds nothing to it.

**It never invokes `overengineering:realign`, and it never enters it.** Not on a verdict that moved,
not on a finding an earlier run already accepted, not when a route is unavailable, not when the
operator asks for it inside this run. Realign is the only mutating surface in this plugin and it is
gated on an explicit per-item human acceptance given at the moment the item is presented; a lane that
can run on a schedule has nobody to give one. Name realign as the next step and stop there — the same
posture `audit` holds, for the same reason. Where the operator wants remediation, they invoke
`overengineering:realign` themselves, in their own session.

**It never writes a `Status`.** Realign is the sole owner of every status transition
(`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, "Status transitions are owned by realign").
This lane *reports* that a status moved; writing one here would put a decision nobody made into the
artifact.

Three writes are sanctioned, and only these:

1. **The spine baseline**, at the memory-tier home resolved below. Memory tier, self-ignored,
   branch-keyed, ephemeral — the same tier and the same disclosure rule as the findings artifact.
2. **The findings artifact itself, written by the composed `overengineering:audit` run**, under that
   skill's own contract. This lane does not write it and does not edit it afterwards.
3. **One queue route**, gated on `queue_route` and on presence, and never on a quiet cycle — see
   "Queued for the human".

State the first and third in the run's opening line, immediately after the home resolves and before
the audit is invoked: *"Read-only pass; realign is never entered. Files written: the spine baseline
at `<resolved path>`, plus whatever the composed audit writes."*

## The load-bearing ordering: capture the prior spine BEFORE the audit runs

**The findings artifact is rewritten in place on every re-run.** A re-audit merges into the existing
file by stable finding id rather than depositing a timestamped sibling
(`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, "Where it lives" and "Re-run merge
semantics"), and the audit writes **per layer as it walks**, so the prior content begins disappearing
at the first layer, not at the end of the run.

There is therefore **no previous artifact left to diff against after the audit has run.** This lane
cannot be "run the audit, then diff": by the time the audit returns, the thing it would diff against
is gone.

The order is:

1. Resolve the home.
2. **Capture the prior spine to the baseline file.**
3. *Then* invoke `overengineering:audit`.
4. Compare the post-run spine against the captured baseline.

**A maintainer who moves step 3 above step 2 silently destroys this lane.** It does not error; it
reports "no baseline, this run establishes one" forever, every cycle, and every cycle looks like a
first run. That failure is invisible from the report, which is why the ordering is stated here as a
contract rather than left as an implementation detail.

## The spine baseline

`spine-baseline.md`, beside the findings artifact in the same resolved home. Its frontmatter, what
its body may and may not carry, its deliberately-not-`overengineering-findings` type, and why it is a
snapshot rather than a second record are owned by
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` under "The spine-capture obligation". **This
skill does not restate them.** One rule binds the run directly:

**Capture never overwrites an unconsumed baseline.** A baseline whose `compared:` stamp is absent
belongs to a cycle that captured and then died before comparing. Keep it, compare against it, and say
so: the report's span then covers more than one cycle and names the `source-date` it is measuring
from. Overwriting it would throw away the only surviving record of where the surface stood.

## Arguments

Parse `$ARGUMENTS`, using the same vocabulary `overengineering:audit` uses, and **pass it through
unchanged**:

- **Layer scope** — one or more values from the layer vocabulary owned by
  `${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`; default `all`. Forwarded verbatim to the
  audit, and it bounds the comparison too (see "Layers that were not walked").
- **`unattended`** (also accepted as `--unattended`) — forwarded verbatim. A scheduled runner, a
  dispatched worker, and a background run all pass it. **Attended is the default**, and the mode is
  never inferred from a probe. Under `unattended` this lane asks nothing, offers nothing, and takes
  the non-interactive collapse of the home-resolution rungs.
- Anything else — a free-text hint. It is **not** forwarded to the audit: a hint narrows what the
  audit attends to, which would make this cycle's walk incomparable with the baseline's. Report the
  hint as declined and why, rather than dropping it silently.

## The run

1. **Resolve the artifact home** by running the whole rung order in
   `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md` — resolve it, never assume the documented
   default's shape. Then emit the opening line above.
2. **Read the artifact at that home.** Its own `branch:` frontmatter is what binds it to a branch;
   the directory is not evidence, because the slug mapping is lossy. Dispose of it:
   - **Absent** → no baseline (below).
   - **`branch:` does not match the current branch** → no baseline, naming both. A spine from another
     branch would report the difference between two branches as churn.
   - **`schema:` unrecognized** → **stop, with a visible message**, before invoking anything. The
     artifact contract makes an unrecognized `schema` a stop for every consumer, and running the
     audit here would rewrite a file this lane cannot read.
   - **Readable and current** → capture it to `spine-baseline.md`.
3. **Invoke `overengineering:audit` via the Skill tool**, passing the layer scope and `unattended`
   exactly as received. Let it run its own contract — home resolution, config resolution, evidence
   assessment, the walk, its own inline summary. **Do not re-derive any of it here.**
4. **Read the post-run artifact**: its spine, its `## Closed since last run` section, its
   `## Suppressed` section, its evidence-availability tokens, and any verdict the audit's own merge
   flagged as having moved under a carried-forward judgment.
5. **Compare**, per "Delta classes" below.
6. **Apply the noise budget**, and report.
7. **Stamp `compared:`** on the baseline file.

**If the audit reports a different resolved home than step 1 captured from, report no delta for this
cycle and name both paths.** Two homes are two histories, and diffing across them manufactures
change. This is a resolution defect to fix, not a delta to report.

## No baseline — a first-class state, not an error

No artifact, a branch mismatch, or a fresh container, worktree, or branch means there is **no prior
spine**. The artifact is ephemeral by design and losing it is expected, not a fault.

In that state the lane:

- says, in one line, **"No baseline; this run establishes one"**, naming the reason (absent /
  branch mismatch, with both branches named);
- runs the audit exactly as it otherwise would, which produces the baseline for the next cycle;
- **reports nothing as a delta** — not the findings, not the counts, not "everything is new". A
  first-run surface is not a change;
- **does not restate the surface.** The composed audit already printed its own inline summary, and
  that summary is the full-surface view. Producing a second one here would be the duplicate record
  the report contract forbids — point at it instead.

## Layers that were not walked

Merge rule 4 carries a finding in an unwalked layer forward **untouched**, marked not re-evaluated
and stamped with the date of the run that produced it. Two obligations follow, and both are
load-bearing:

- **Every finding in a layer absent from this run's `scope` is excluded from the comparison
  entirely.** It is not unchanged-and-checked, and it is emphatically not closed. It contributes to
  no delta class.
- **The report names the unwalked layers once, as a coverage line, with the count of findings held
  in them** — never as findings. A layer-scoped cycle that read as a clean bill of health for the
  whole surface would be worse than no cycle at all.

The converse case is real too. A layer walked **this** run but absent from the **baseline** run's
`scope` carries baseline rows that are themselves stale carry-forwards. A verdict move there is
genuine, but its "since" is the older run's stamped date, not the baseline artifact's `date`. Take
the per-finding stamp merge rule 4 wrote where one exists, and the baseline's `date` otherwise, so
the report's span is honest per finding rather than per run.

## Delta classes — what the merge already computes, and what this lane computes

The artifact's own re-run merge already computes several of these. **Read them; never re-derive
them** — a second derivation is a second answer that can disagree with the first.

| Class | Computed by | This lane's job |
|---|---|---|
| **Closed finding** | the merge, rule 3 | **Read `## Closed since last run`.** It carries the reason class (`artifact absent`, `renamed to <successor id>`, `layer no longer configured`), which a spine comparison cannot produce. Ignore a row whose id the baseline never carried — that is a stale section, reported once as a contract anomaly, not as a delta. |
| **Verdict moved under a carried-forward judgment** | the merge, rule 5 | **Read the merge's flag and carry it.** Do not shadow it with a second detection: rule 5's flag is authoritative for *"a human's decision is now out of date"*, and this lane's comparison only supplies the verdict pair and the status alongside it. One row, not two. |
| **New finding** | the merge, rule 2 (`Status: OPEN` on an id it had not seen) | Cross-check against the baseline spine and report the verdict it opened with. |
| **Suppression change** | the merge, via `## Suppressed` | Read it. A finding newly suppressed, or an entry that stopped suppressing, changes what the report may omit. |
| **Verdict change on an unjudged finding** | **this lane** | Same id, `Status: OPEN` on both sides, different `Verdict` token. |
| **Status change** | **this lane** | Same id, different `Status`. The audit only ever writes `OPEN` on a new finding and carries everything else forward, so a status that moved between two audit-driven runs means **a human acted through realign in between**. |
| **Member verdict change** | **this lane** | Within one container id, members matched by member id, read for a changed verdict token. |
| **Evidence availability** | **this lane** | Per-tier token comparison. Run-level, not per-finding. |

**Two spine fields can never move under a stable id, so they are never a delta class.** `layer` feeds
the id's `check` constituent and `artifact` feeds its `sites`, so changing either changes the id: the
old finding closes and a new one opens. A lane reporting "layer changed" has derived an id wrongly.

**Evidence-only change is out of scope, by construction — not by choice.** Evidence, liveness,
intent, rediscovery, cost, and owner are prose, recomputed fresh every run, and deliberately excluded
from the spine. A spine comparison cannot see a change in them, and no threshold makes it able to.
Saying "evidence updates are covered" would be claiming a capability the mechanism does not have.
What this lane *can* see is the consequence: evidence that moved enough to change a verdict shows up
as a verdict change, and evidence whose whole **tier** appeared or vanished shows up in the
run-level evidence-availability line. Everything between those two is invisible here, and an operator
who needs it reads the artifact.

## The noise budget

Every class is disposed as **list**, **count**, or **omit**. Listed items appear as rows; counted
items appear only as a number in the counts table; omitted classes appear nowhere. The keys named
below are read, never redefined here: each key's type, default, and layering are owned by
`${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md` under `delta_noise_budget`.

**Two classes are always listed, whatever the budget says:** a verdict that moved under a
carried-forward judgment (merge rule 5), and a status change. They are not keys held at a locked
default — they are not keys at all, and the reasoning is owned by that same section of
`consumer-config.md`.

The classes a key governs:

| Class | Disposition | The rule a reader can apply |
|---|---|---|
| **New finding** | list when its verdict is one `new_finding_verdicts` selects; count otherwise | A new incumbent that already earns its keep (`KEEP`) is not news for a retirement lane. |
| **New `UNPROVEN` finding** | list the top `unproven_head` off the audit's own carry-cost ranking; count the rest | An evidence desert produces UNPROVEN in bulk, and listing it is exactly the undifferentiated wall §8 already refuses. The ranking is the audit's; this lane takes its head and does not re-rank. |
| **Verdict change, unjudged finding** | list the moves `verdict_change` selects — boundary crossings only, every move, or none | A boundary crossing is any of: `KEEP` ↔ any of `RETIRE`/`DOWNGRADE`/`CONSOLIDATE`; either side is `FLAG-FOR-HUMAN`; or the verdict entered or left `UNPROVEN`. A move *within* the retirement-direction set (`DOWNGRADE` → `CONSOLIDATE`) changed the shape of a recommendation nobody has acted on yet, not its disposition. |
| **Closed finding** | list the closures `closed_findings` selects — unexpected only, all, or none | A close is expected when its prior status was `REALIGNED` — the mechanism is gone because a human removed it, and re-reporting it is noise realign's own contract already anticipates. Every other close is unexpected: an `artifact absent` close under `OPEN` or `REJECTED` means something vanished that nobody decided to remove, and `renamed to …` and `layer no longer configured` are surface changes worth a glance. |
| **Member verdict change** inside a container whose own verdict did not move | as `member_verdicts` says — counted, surfaced as rows, or omitted | A container's own verdict is the finding; a member move under an unchanged container is a detail, and container counts and member counts are two grains that must never be summed. |
| **Evidence availability** | one line, always | `unchanged`, or the tiers that moved. When a tier moved, it leads the report: it changes what UNPROVEN means for every row beneath it. |

**The volume cap.** When the listed set exceeds `max_items`, list the head and give the residue as
counts with a pointer to the artifact. Rank the head by class in this order: rule-5 flags → status
changes → boundary-crossing verdict changes → new retirement-direction findings by the audit's
carry-cost ranking → unexpected closures. **Within a class that carries no ranking of its own, break
the tie by the artifact's stable total order** (`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`,
"Ordering") — class rank alone leaves the truncation point undetermined, and two runs over identical
input that cut a different head report a difference that did not happen. A delta report longer than
an operator will actually read has re-served the whole surface by another route.

**The quiet cycle.** When nothing clears the budget, say exactly that in one line, print the counts
table, and **stop**. Do not restate the surface, do not list the counted classes as rows, do not
offer a summary of what is still open, and do not route anything. A quiet cycle is the expected
outcome of a healthy surface.

**The lane always reports something, even when quiet.** Total silence is indistinguishable from a
lane that stopped running.

## Queued for the human

A verdict change is never acted on here. It is **queued**, which means exactly two things:

**1. In the report, always.** A `## Queued for the human` section, one row per surfaced verdict
change, carrying the finding id, the verdict pair (`<was>` → `<now>`), the current status, the layer,
and the single act it invites: `overengineering:realign <finding-id>`. Rule-5 flags lead the section;
they are the rows where the evidence moved under a decision already made.

**2. Routed to a tracker, under `queue_route` and presence-gated.** The route is a **notification,
never a remediation**: it carries ids and verdict pairs and nothing that instructs a change. Read
`queue_route` (`${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`, under `delta_noise_budget`)
*before* probing for a tracker — an operator who declined the route is not to be probed
on their behalf and then overridden. Whichever row below the run takes, record **the route decision
and the presence answer** in the report, so a skipped route is visible rather than silent.

| `queue_route` | Condition | What the lane does |
|---|---|---|
| `auto` | A work-item tracker is reachable through `work-items:track`, and that plugin is installed | Maintain **one** open queue item per branch, carrying the current queued rows |
| `auto` | No such tracker is reachable | Decline the route, naming the absence. The report's own `## Queued for the human` section is the queue — stated plainly, together with the fact that no durable route exists, so the queue lives only as long as this run's output |
| `inline` | Not consulted — no probe is made | Decline the route **unconditionally**, naming the operator's setting as the reason. The report's own section is the queue, exactly as in the row above |

Rule 1 is unconditional in every row: the queue appears in the report whether or not it is also
routed. A declined route changes where the queue is *durable*, never whether it is *reported*.

Four rules keep a taken route from becoming the nag:

- **One item per branch, updated — never a second one.** A re-run replaces the item's rows; it does
  not open another and does not append a cycle log.
- **A quiet cycle does not touch the item at all.** No "nothing changed this cycle" comment. That
  comment *is* the nag.
- **A row whose finding now carries a non-`OPEN` status is removed, not restated.** The human
  dispositioned it; re-raising it is the noisy-repeat failure the durable judgment record exists to
  prevent.
- **The lane never closes the item.** Closing is the human's act, and a lane that closes its own
  escalations has escalated to itself.

## The report

The composed audit already owns the full-surface view: the findings artifact is the single source of
truth and the audit's inline summary is its navigation aid
(`${CLAUDE_PLUGIN_ROOT}/skills/audit/context/report-template.md`). **This lane adds one short delta
view and no third record.** In order:

1. **The read-only line**, plus the span this comparison covers: `source-date` → this run's `date`,
   and whether it covers more than one cycle.
2. **Coverage**: layers walked this run; layers not walked, with the count of findings held in them.
3. **Evidence availability**: `unchanged`, or the tiers that moved — first when it moved.
4. **The counts table**: one row per delta class, listed / counted / omitted.
5. **The listed rows**, in the cap's rank order.
6. **`## Queued for the human`**, always — with the route decision and the presence answer behind
   it (or that presence was not consulted, under `queue_route: inline`).
7. **The next step, named and not taken**: `overengineering:realign` executes accepted findings
   behind an explicit per-item human gate. Never start it.

## Recurring wiring

How a consumer schedules this lane — a fixed-interval loop, a scheduled task, a CI schedule, or a
recurring tracker item — with the trade each shape makes, is in
[skills/delta/context/recurring-wiring.md](context/recurring-wiring.md). **This plugin adopts no
schedule of its own and ships no schedule file**; the cadence is the consumer's decision, and a lane
that scheduled itself on install would be an unratified standing commitment.

## Consumer-agnostic

Nothing here assumes an organization, a repository, a forge, a CI system, a scheduler, a branch name,
or an agent harness. Layers are the ten forge-neutral names in the artifact's vocabulary; the tracker
route is presence-gated with a named inline fallback; the cadence is documented, never adopted.

## Gotchas

- **Capture, then audit.** The single ordering the whole lane rests on, and the one a refactor is
  most likely to reverse. See the section above.
- **A layer-scoped cycle is not a clean bill of health.** Unwalked layers contribute to no delta
  class and are named as coverage, never as findings.
- **The first run of every branch has no baseline.** Branch-keyed and ephemeral is the artifact's
  design, not a fault, and a per-branch first cycle is normal rather than a signal.
- **Do not diff the prose.** Two independent prose passes over an unchanged tree are never
  byte-identical, and live evidence sources move between runs by design. A prose diff reports model
  noise as change.
- **A verdict change is not an authorization.** It is queued. Nothing in this lane reaches
  `overengineering:realign`, including the operator asking for it mid-run.
- **Counted is not hidden.** Every counted item is in the artifact with its full evidence; the budget
  decides what the delta *view* leads with, never what the audit records.
