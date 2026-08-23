---
description: "Report only what changed in the enforcement surface since the last audit. Re-runs `overengineering:audit`, compares this run's findings spine against the one the previous cycle left behind, and captures a fresh baseline for the next — new clutter, verdict moves, closures, status changes — filtered through a configurable noise budget, so a recurring run is a short delta instead of the whole surface again. Read-only always: it never invokes or enters `overengineering:realign`, never writes a Status, and never touches the surface it reads; verdict changes queue for the human. A first run establishes a baseline and reports no deltas. Use when: 'what changed since the last audit', 'delta since the last run', 'run the enforcement audit on a schedule', 'recurring overengineering check', 'only show me what is new', 'did any verdict move', 'weekly automation-cruft check'. Pass layers to scope the pass and `unattended` for a scheduled or dispatched run; both pass straight through to the audit."
argument-hint: "[layer ...] [unattended] — layer: agent-hooks|agent-instructions|repo-hooks|vcs-hooks|ci-lanes|gate-scripts|satellite-workflows|branch-protection|forge-apps|external-integrations|all (default: all)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: anytime
  summary: Re-run the enforcement-surface audit and report only what moved since the last run
---

## Pre-computed context

- Branch: !`git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "no branch ref (detached HEAD or no checkout)"`

Deliberately one line. A precompute block carrying a git command **and** more than one injection line
is refused outright in a worktree-isolated agent, which is exactly the dispatched context a scheduled
run of this lane arrives in. The baseline's UTC stamps are read with an ordinary `date -u
+%Y%m%dT%H%M%SZ` call at the moment they are written, where they are accurate anyway.

**`symbolic-ref`, not `rev-parse --abbrev-ref`, and the difference is the whole guard.**
`git rev-parse --abbrev-ref HEAD` returns the literal string `HEAD` on a detached checkout — a value
that looks like a branch name, keys every ref to one home, and compares equal to itself, so the
branch-match check below would pass for two entirely different refs. `git symbolic-ref` fails instead
of inventing an identity, which is what this lane needs. Scheduled runners commonly check out
detached, so this is the ordinary case here, not the exotic one. What the lane does with an
unresolved branch identity is in "The run" step 1.

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

1. **The spine baseline**, at the memory-tier home resolved below, written **at the end of the
   cycle** from this run's post-audit spine. Memory tier, self-ignored, branch-keyed, ephemeral —
   the same tier and the same disclosure rule as the findings artifact. Two cases write it earlier or
   not at all: a **bootstrap** cycle captures pre-audit because it has nothing else to compare
   against, and a cycle whose branch identity is unresolved writes **no** baseline at all.
2. **The findings artifact itself, written by the composed `overengineering:audit` run**, under that
   skill's own contract. This lane does not write it and does not edit it afterwards.
3. **One queue route**, gated on an opt-in `queue_route: auto` and then on presence, and never on a
   quiet cycle — see "Queued for the human".

State the first and third in the run's opening line, immediately after the home resolves and before
the audit is invoked: *"Read-only pass; realign is never entered. Files written: the spine baseline
at `<resolved path>`, at the end of this cycle, plus whatever the composed audit writes."*

## The load-bearing mechanic: the baseline is the PREVIOUS cycle's post-audit spine

Two independent things have to be right here, and each fails silently on its own.

**First: a spine must be persisted, because the artifact is rewritten in place on every re-run.** A
re-audit merges into the existing file by stable finding id rather than depositing a timestamped
sibling (`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md`, "Where it lives" and "Re-run merge
semantics"), and the audit writes **per layer as it walks**, so the prior content begins disappearing
at the first layer, not at the end of the run. There is therefore **no previous artifact left to diff
against after the audit has run**, and this lane can never be "run the audit, then diff the file". A
separately persisted spine is mandatory. That reason is unchanged and still load-bearing.

**Second: the persisted spine has to be captured at the *end* of a cycle, not the start.** A cycle
that captures its baseline from the artifact as it stands at the start of the run captures a file a
human may already have edited. `Status` is exactly that field: realign writes it, a human runs
realign **between** cycles, and the audit only ever writes `OPEN` on a newly-seen id and carries every
other status forward untouched. So a start-of-cycle capture already contains the new status, the
audit carries that same status through, and baseline and post-audit spine agree on `Status` for every
pre-existing finding — the status-change class is dead by construction, in precisely the case it
exists to catch.

The mechanic is therefore:

1. Resolve the home and the branch identity.
2. **Read the stored `spine-baseline.md` — the *previous* cycle's post-audit spine.** That, and
   nothing captured this cycle, is what the comparison measures from.
3. Invoke `overengineering:audit`.
4. Compare **this run's post-audit spine** against the stored baseline.
5. **Capture this run's post-audit spine over the stored baseline**, for the next cycle to compare
   against.

The pre-audit capture survives in exactly one place: **the bootstrap cycle** below, where no stored
baseline exists yet and a pre-audit capture is the only baseline obtainable.

**A maintainer who breaks either half does not get an error, they get a silently useless lane.**
Collapse step 5 into step 2 and the comparison never sees a status change, while every other class
still reports plausibly, so the loss is invisible. Drop the persistence entirely and every cycle
reports "no baseline, this run establishes one" forever and every cycle looks like a first run. Both
failures are invisible from the report, which is why the mechanic is stated here as a contract rather
than left as an implementation detail.

## The bootstrap cycle — the one pre-audit capture

A home can hold a findings artifact and no `spine-baseline.md`: audits were run manually here before
this lane ever ran. That first delta cycle **captures the artifact's spine pre-audit** so it has
something to compare against, and it says so in the report.

**A bootstrap cycle cannot detect a status change, and it says that too.** Its baseline is the
artifact as it stands *after* whatever realign runs already happened, and the audit carries those same
statuses forward, so both sides of the comparison hold the identical `Status` for every pre-existing
finding. The class is not suppressed; it is unobservable this once. **The next cycle can see one**,
because its baseline is this cycle's post-audit spine, taken before any later realign ran.

Every other delta class works normally on a bootstrap cycle: a verdict really can move between the
artifact's stored judgment and this run's fresh one.

## The spine baseline

`spine-baseline.md`, beside the findings artifact in the same resolved home. Its frontmatter, what
its body may and may not carry, its deliberately-not-`overengineering-findings` type, and why it is a
snapshot rather than a second record are owned by
`${CLAUDE_PLUGIN_ROOT}/context/findings-artifact.md` under "The spine-capture obligation". **This
skill does not restate them.** Two rules bind the run directly:

**A capture never replaces a baseline this cycle did not consume.** The end-of-cycle capture is
earned by having completed the comparison, and nothing else earns it. Where the cycle stopped short —
the audit was never invoked, it failed, the schema was unrecognized, the homes disagreed, the branch
identity was unresolved — the stored baseline stays exactly as it is and this run writes none.
Overwriting it would move the comparison's origin silently forward past a cycle nobody ever compared,
and whatever moved in between would then be reported by no cycle at all.

**A baseline older than one cycle widens the span rather than being discarded.** When the stored
baseline's `source-date` predates the immediately preceding cycle — an interrupted cycle left it
unconsumed, or a cycle consumed it and died before capturing its own — compare against it anyway and
say so: the report's span then covers more than one cycle and names the `source-date` it is measuring
from.

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

1. **Resolve the branch identity, then the artifact home.** The precompute above yields a branch name
   or the `no branch ref` string. When it yields the string, the checkout is detached (or absent) and
   **`HEAD` is never accepted as a branch identity** — see "A detached checkout has no branch
   identity" below for what to do and what not to.
   Resolve the home by running the whole rung order in
   `${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md` — resolve it, never assume the documented
   default's shape. Then emit the opening line above.
2. **Read the stored `spine-baseline.md` at that home.** This is the comparison baseline: the
   previous cycle's post-audit spine. Dispose of it:
   - **Present, `branch:` matches the resolved branch identity** → this is the baseline. Note its
     `source-date`; where it predates the immediately preceding cycle, the span widens and the report
     says so.
   - **Present, `branch:` does not match** → no baseline, naming both. A spine from another branch
     would report the difference between two branches as churn.
   - **Absent, and a findings artifact exists at the home** → **bootstrap cycle.** Read the artifact,
     dispose of it as below, and capture its spine pre-audit as this cycle's baseline. Say in the
     report that this is a bootstrap and that a status change is unobservable this cycle.
   - **Absent, and no findings artifact either** → no baseline (below).

   Disposing of the findings artifact, on a bootstrap or when the baseline's provenance needs
   checking, follows its own frontmatter: its `branch:` is what binds it to a branch, and the
   directory is not evidence, because the slug mapping is lossy. A `branch:` that does not match is
   no baseline, naming both. An **unrecognized `schema:`** is a **stop, with a visible message**,
   before invoking anything — the artifact contract makes an unrecognized `schema` a stop for every
   consumer, and running the audit here would rewrite a file this lane cannot read.
3. **Invoke `overengineering:audit` via the Skill tool**, passing the layer scope and `unattended`
   exactly as received. Let it run its own contract — home resolution, config resolution, evidence
   assessment, the walk, its own inline summary. **Do not re-derive any of it here.**
4. **Read the post-run artifact**: its spine, its `## Closed since last run` section, its
   `## Suppressed` section, its evidence-availability tokens, and any verdict the audit's own merge
   flagged as having moved under a carried-forward judgment.
5. **Compare** this run's post-audit spine against the baseline from step 2, per "Delta classes"
   below.
6. **Apply the noise budget**, and report.
7. **Stamp `compared:`** on the stored baseline, then **capture this run's post-audit spine over it**
   — the baseline the *next* cycle compares against. Both acts are earned by step 5 having completed;
   where it did not, leave the stored baseline untouched and write nothing.

**If the audit reports a different resolved home than step 1 resolved, report no delta for this
cycle, name both paths, and leave the stored baseline untouched.** Two homes are two histories, and
diffing across them manufactures change. This is a resolution defect to fix, not a delta to report.

## A detached checkout has no branch identity

`git rev-parse --abbrev-ref HEAD` answers `HEAD` on a detached checkout. That is a string, not an
identity, and treating it as one breaks this lane twice over: every ref keys to the same
`<branch-slug>` home, and the branch-match check in step 2 compares `HEAD` to `HEAD`, passes, and
accepts some other ref's spine as this ref's baseline — after which the lane reports the difference
between two refs as a delta. Scheduled runners very commonly check out detached, so this is the
ordinary case for the mode this lane was built for, which is why the precompute uses
`git symbolic-ref` and refuses to invent a name.

When the branch identity does not resolve:

- **Prefer a logical ref where the environment supplies one.** Some execution environments hand the
  run the ref it was launched for even though the checkout is detached. Where such a value is present
  and names a branch, use it as the branch identity for both the home key and the match check, and
  name in the report where it came from. **No vendor's variables are named here or assumed** — this
  plugin is consumer-agnostic, and hardcoding one CI system's environment would be a claim about the
  consumer's toolchain that the rest of this plugin refuses to make.
- **Otherwise, treat the run as no baseline and say why** — "detached checkout, no logical ref
  supplied; no branch identity, so nothing is compared". Do not fall back to `HEAD`, to the commit
  sha, or to whatever home the slug happens to produce, and do not compare.
- **Capture no baseline either.** With no branch identity, a capture would land in a home keyed by
  something every ref shares, where the next detached run of a *different* ref would read it as its
  own. This is the one no-baseline state that does **not** establish a baseline for the next cycle,
  and the report says so rather than implying the next run will have one.

The audit still runs, exactly as it otherwise would; what is declined is the comparison and the
capture, not the pass.

## No baseline — a first-class state, not an error

No stored baseline and no artifact, a branch mismatch, an unresolved branch identity, or a fresh
container, worktree, or branch means there is **no prior spine**. Both files are ephemeral by design
and losing them is expected, not a fault.

In that state the lane:

- says, in one line, **"No baseline; this run establishes one"**, naming the reason (absent /
  branch mismatch, with both branches named) — except under an unresolved branch identity, which
  establishes nothing and says so instead, per the section above;
- runs the audit exactly as it otherwise would, and captures its post-audit spine at the end of the
  cycle as the baseline for the next one;
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
| **Status change** | **this lane** | Same id, different `Status` between the previous cycle's post-audit spine and this one's. The audit only ever writes `OPEN` on a new finding and carries everything else forward, so a status that moved means **a human ran realign between the two cycles** — which is exactly why the baseline is captured after the audit rather than before. A start-of-cycle capture would already hold that new status and this class could never fire; a **bootstrap** cycle has such a baseline and cannot see one, and says so. |
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

The remaining classes, each named with the key that governs it where one does:

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

**2. Routed to a tracker — opt-in under `queue_route`, then presence-gated.** The route is a
**notification, never a remediation**: it carries ids and verdict pairs and nothing that instructs a
change. Read `queue_route` (`${CLAUDE_PLUGIN_ROOT}/reference/consumer-config.md`, under
`delta_noise_budget`) *before* probing for a tracker — an operator who has not asked for the route is
not to be probed on their behalf and then routed anyway. Whichever row below the run takes, record
**the route decision and the presence answer** in the report, so a skipped route is visible rather
than silent.

**The durable route requires the operator to have set `queue_route: auto` in tracked config, and an
unset key means report-only.** The reason is the tracker's own authorization gate, not a preference
about verbosity: `work-items:track`'s `add` action holds that *"Never file a work item on inferred
intent. … An explicit user `/work-items:track add ...` invocation IS the authorization;
model-initiated filing is not"* — so an unattended scheduled cycle, which is the mode this lane
exists for, has no authorization to file anything and a conforming tracker must refuse it. Setting
the key **is** the explicit, recorded authorization the gate asks for, given once by a human in a
file. **Do not flip this default back to `auto`**: a default-on route makes the lane's ordinary
unattended path a request the tracker is contractually obliged to decline.

| `queue_route` | Condition | What the lane does |
|---|---|---|
| unset (the default, `inline`) | Not consulted — no probe is made | Decline the route **unconditionally**, naming the absent opt-in as the reason. The report's own `## Queued for the human` section is the queue — stated plainly, together with the fact that no durable route exists, so the queue lives only as long as this run's output |
| `inline`, set explicitly | Not consulted — no probe is made | Identical to the row above, naming the operator's setting as the reason |
| `auto` | A work-item tracker is reachable through `work-items:track`, and that plugin is installed | Maintain **one** open queue item per branch, carrying the current queued rows. The operator's tracked `queue_route: auto` is the authorization carried into that filing, and is named as such |
| `auto` | No such tracker is reachable | Decline the route, naming the absence. The report's own section is the queue, exactly as in the first row |

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
   it (or that presence was not consulted, because `queue_route` is unset or `inline`).
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
route is opt-in and then presence-gated, with a named inline fallback; a logical ref is taken from
the environment where one is supplied, without naming any vendor's variables; the cadence is
documented, never adopted.

## Gotchas

- **The baseline is the previous cycle's post-audit spine, captured at the end of that cycle.** Not
  a capture taken at the start of this one — that baseline already holds whatever status realign
  wrote in between, so the status-change class could never fire. The one exception is the bootstrap
  cycle, which is named as such and cannot see a status change. See the section above.
- **`HEAD` is not a branch name.** A detached checkout — the normal shape for a scheduled runner —
  makes `rev-parse --abbrev-ref` answer `HEAD`, which keys every ref to one home and compares equal
  to itself, so a cross-ref spine would sail through the branch-match check. Resolve a logical ref
  where the environment supplies one; otherwise decline to compare and decline to capture.
- **A layer-scoped cycle is not a clean bill of health.** Unwalked layers contribute to no delta
  class and are named as coverage, never as findings.
- **The first run of every branch has no baseline.** Branch-keyed and ephemeral is the design of both
  files, not a fault, and a per-branch first cycle is normal rather than a signal.
- **Do not diff the prose.** Two independent prose passes over an unchanged tree are never
  byte-identical, and live evidence sources move between runs by design. A prose diff reports model
  noise as change.
- **A verdict change is not an authorization.** It is queued. Nothing in this lane reaches
  `overengineering:realign`, including the operator asking for it mid-run.
- **Counted is not hidden.** Every counted item is in the artifact with its full evidence; the budget
  decides what the delta *view* leads with, never what the audit records.
