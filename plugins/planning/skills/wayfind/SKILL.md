---
description: "Chart a too-big, still-foggy effort as a decision map on the work-item tracker and work its frontier one decision at a time until it graduates to a Brief, PRD, or PLAN. Use when an interview outgrew one session: 'turn this into a map', 'this is a huge foggy effort', 'I don't even know the questions yet', 'map this out', 'plan-the-plan'. Not the first step: a new effort starts at /planning:interview. Already sharp tickets: /work-items."
argument-hint: "[chart|work] [topic]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: contract
  summary: Chart a too-big, foggy effort as a decision map worked one decision at a time
---

**Arguments.** `[chart|work] [topic]`. e.g., /planning:wayfind chart <topic>, /planning:wayfind work

## Pre-computed context

Container label (an ERROR line here means `config.container_label` is not a string; fix `.work-item-tracker.json` before continuing): !`jq -r 'if .config.container_label == null then "work-map" elif (.config.container_label | type) == "string" then .config.container_label else "ERROR: config.container_label must be a string (got \(.config.container_label | type))" end' .work-item-tracker.json 2>/dev/null || echo "work-map"`

Open maps: list them at the start of every action with
`/work-items:track list --label '<container label>' --state open`, invoked via the Skill tool
([`context/tracker-mechanics.md`](context/tracker-mechanics.md)). Without the `work-items` plugin,
wayfind cannot reach the tracker: say so and stop.

## Variables

Arguments: `$ARGUMENTS`

## Purpose

For an effort **too big to hold at once AND too foggy to ticket**, where half the questions cannot
yet be phrased: turn it into a shared **decision map** on the work-item tracker, then work the
map's frontier one decision at a time until a real destination (Brief / PRD / PLAN) can be handed
onward. It is the escalation from an interview that outgrew one session, never the first step: a
brand-new effort starts with `/planning:interview`.

**Plan, don't do.** A map holds *decisions*, not build work. Each resolved decision either sharpens
the map or graduates to the destination. Once the destination is coherent, the map closes and the
normal pipeline (`/planning:interview → /planning:design → /planning:plan →
/implementation:implement`) takes over. The map lives as native tracker primitives, each decision
routes to a first-party skill, and execution artifacts live in the memory slice
`<memory_dir>/<slug>/` (default `.work/`; see
[`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md)),
never in the map.

## The fog test (the one call that governs everything)

For every uncertainty, ask: **can I phrase it as a sharp question?**

- **Sharp** (you can state the question, even if you can't answer it yet, even if it's blocked) →
  a **decision item** on the map (a typed sub-issue).
- **Foggy** (you can't yet put words to what's uncertain) → **prose** in the map's
  *Not-yet-specified* section, until working the map makes it sharp enough to phrase.

Sharpness, not blockedness, is the line: a blocked-but-phrasable question is a ticket; an
unblocked-but-unphrasable worry is fog.

## Refer by name

In everything the human reads (chart report, work frontier, map-body index lines), name each item
by **title**, number as a link or suffix. Never a wall of bare `#42, #43, #44`.

## Action Router

Parse the first token of `$ARGUMENTS`.

| Argument | Action | When |
|----------|--------|------|
| *(empty)* | **auto** | Open map for the topic exists → `work`; else → `chart` |
| `chart [topic]` | **Chart** | Build or extend a decision map. **Interactive only**. Refuses non-interactive sessions (charting burns assumptions that need a human) |
| `work [#map]` | **Work** | Pick one frontier item and drive it to resolution |

## Chart mode

Charting needs a human in the loop, and a session cannot detect that on its own, so the caller
declares it (the same rule `/planning:interview` applies): when the invocation says the run is
unattended (a loop, a spawned worker, a `claude -p` run, another skill's chain), STOP and report
that charting needs an interactive session. Do not fabricate a map.

1. **Survey + fog test.** Ground in the effort (any existing `<memory_dir>/<slug>/`, recent
   commits, the topic).
   - **Seed from the interview:** when the slice holds an interview ledger
     (`interview-checklist.md`), its settled answers go into one seed decision item whose
     resolution comment lists them; close it at once with one *Decisions-so-far* pointer (the
     work-mode step 5 sequence). Its open, deferred and blocked questions become candidate
     decision items. Its self-answered facts, constraint ledger, `## Starting point` line, and
     session-shorthand glossary are distilled into *Notes* as text, never as a path, so nothing
     the interview already asked is asked again.
   - Sort every remaining uncertainty through the fog test: sharp → candidate decision item;
     foggy → *Not-yet-specified* prose.
   - **No-fog bail-out:** if the survey leaves *both* halves of the trigger unmet (every
     uncertainty is already sharp, or the whole effort fits one session), the effort does not
     need a map. STOP and route out instead of fabricating one: a single contract to lock →
     invoke `/planning:interview` via the Skill tool; a set of sharp tickets →
     `/work-items:decompose` (or `/work-items:track add` for one ticket); small enough to just
     do → say so. The trigger is too-big AND foggy, both, never either alone. Seeded rows are
     sharp by construction, so the fog must come from the survey; a seeded interview with no fog
     goes back to its own handoff and resume.
   - **New-effort gate**, checked after the bail-out: when neither the slice nor this
     conversation holds an interview of the effort, STOP and recommend `/planning:interview`
     first; chart only if the user still asks for a map after hearing that.
2. **Create or extend the map issue.** On first use in a repo, resolve the container label (the
   seam's `config.container_label` key, default `work-map`; snippet in
   `context/tracker-mechanics.md`), then **verify** the wayfind label taxonomy (the container
   label, `wayfind: *`, `needs-human`) is present: an unknown `--label` fails the create. Honor
   the consuming repository's declared label ownership: if it names a label-as-code source of
   truth, STOP and report the exact missing set to that owner; otherwise report the set and ask
   the user how labels are provisioned. Never create labels ad hoc from this skill. Then create
   one issue labeled with the bare container label (+ any repo program labels). Its body carries
   five sections:
   - **Destination**: where this is going once the fog clears.
   - **Notes**: durable pointers only (PRs, committed docs, prior items, external links).
     Memory-tier `<memory_dir>/` artifacts are checkout-local, so distill their relevant content inline
     instead of pointing at paths other readers cannot resolve.
   - **Decisions-so-far**: a *pointer index* of resolved-in-scope decisions. Each home is its own
     item's resolution comment, never recopied here; wrongly scoped closures get no pointer.
   - **Not-yet-specified**: fog, as prose. Fog never graduates into Out-of-scope.
   - **Out-of-scope**: scope exclusions, not unphraseable fog.

   Template and tracker actions: [`context/tracker-mechanics.md`](context/tracker-mechanics.md).
3. **Create typed decision items** as sub-issues of the map, one per sharp question. The type
   label sets the routing target and default mode (the type table in Work mode step 4). Wire
   `blocked-by` edges only where one decision genuinely gates another; never invent edges to
   impose order.
4. **Materialize the mode** on each item at creation: HITL types (`interview`, `design`,
   `prototype`) get the `needs-human` label; `research` omits it (autonomous-capable); `task` is
   per-item. The presence or absence of `needs-human` is the only mode mechanism; no `Mode:` body
   field.
5. **Hand off to `work`.** Report the frontier (open, unblocked, unassigned items) **by title**,
   number as a link or suffix, and recommend `/planning:wayfind work`. If the frontier holds
   `research`-typed items, offer to fire them now in parallel (work mode's research exception);
   their resolutions often sharpen the remaining fog before the first HITL session.

## Work mode

1. **Session-start reclaim + map hygiene.** Reclaim any of your own stale in-progress items
   (idempotent). Check the map's invariants: every closed **in-scope** decision has a
   *Decisions-so-far* pointer line (closed-as-out-of-scope items have an Out-of-scope line
   instead; closed-as-moot items have only their closing comment); no item resolved-in-comment
   but still open; no Not-yet-specified prose that an item already charts (delete it). Fix
   violations before proceeding.
2. **Compute the frontier.** `frontier = open ∧ zero OPEN blockers ∧ unassigned` (count open
   blockers, not the raw edge count). In a non-interactive session, filter OUT `needs-human`
   items; if that empties the frontier, STOP with a truthful "all remaining decisions need a
   human". Never resolve a HITL item by standing in for the human.
3. **Pick one and claim it** (the sibling claim model through `/work-items:track start`:
   assignee + lease with a race-safe back-off, no claim label; see
   [`context/tracker-mechanics.md`](context/tracker-mechanics.md)). One item per session, with one
   exception: **`research`-typed items may be burned down in parallel.** When the frontier holds
   several, claim each individually (same protocol, one claim per item) and dispatch
   `/discovery:research` per item (it already runs in a fresh-context subagent). Graduate each on
   completion per step 5; the resolution comment is the finding's durable home, research scratch
   stays in `<memory_dir>/<slug>/`. Never fan out a `needs-human` item.
4. **Route by type**. Invoke the target skill directly; its own Q&A supplies the HITL loop:

   | Type label | Mode | Routes to |
   |---|---|---|
   | `wayfind: research` | autonomous-capable | `/discovery:research` (falls back to inline research if not enabled) |
   | `wayfind: interview` | HITL | `/planning:interview` |
   | `wayfind: design` | HITL | `/planning:design`, or `/event-storming:methodology` / `/event-storming:simulation` when the item is domain/event-model work |
   | `wayfind: prototype` | HITL | `/prototype:pressure-test` (behaviour/feasibility) or `/prototype:explore-directions` (design/UX). The item body says which |
   | `wayfind: task` | per-item | Direct decision-unblocking work. No feature code, no PR tie |

5. **Graduate on every resolution.** Resolved **in scope**: post the resolution as a comment on
   the item, add its one-line pointer (title, number as suffix) to *Decisions-so-far*, then close
   the item (comment → index → close, as one atomic sequence). **Wrongly scoped** (on the tracker
   but not this effort): add one Out-of-scope line linking it, then close it, with no
   Decisions-so-far pointer. Fog stays in Not-yet-specified and never graduates into
   Out-of-scope. If the resolution sharpened previously-foggy uncertainty, chart the new sharp
   items now and delete that prose from Not-yet-specified.
6. **Sweep the map after every resolution.** Reread the open items and closed decisions against
   what was just decided:
   - An open item whose premise the resolution invalidated: rewrite its question if one still
     stands, then reset its type label, mode label and blocked-by edges as chart steps 3-4
     require; otherwise close it as not planned with a comment linking the resolution that made
     it moot. A moot item gets no line in either index.
   - A closed decision the resolution shows was wrong: open a new decision item that links the
     old one, with its type and mode labels set as chart step 4 requires, and work it like any
     other. When it resolves, add its pointer to Decisions-so-far and change the old decision's
     line to `<old title> (#<old>): superseded by <new title> (#<new>) (resolved <date>)`.
     Never reopen the old item or edit its resolution comment.
7. **Map closure → destination handoff.** When the frontier is empty and every decision item is
   closed, close the map issue and hand the destination onward (`/planning:interview` or
   `/planning:prd` for a Brief/PRD; `/planning:design`, ahead of `/planning:plan`, for a PLAN).

## Escalation. Pull the user back to charting at choke points

`/planning:wayfind`'s description carries the proactive trigger. The sibling skills carry
**pull-back lines**: when `/planning:interview`, `/planning:plan`, or `/implementation:implement`
hits a task that is clearly too-big-AND-foggy for their stage, they name `/planning:wayfind` as the escalation, **guiding the
user, never auto-switching**. Their pull-back wording lives in each of those skills; this skill
owns the trigger's meaning (too-big + fog, both, not either alone).

## Composition

| When | Skill | How it composes |
|---|---|---|
| Effort too big AND foggy to ticket | **`/planning:wayfind`** (this) | Produces a decision map; graduates to a destination |
| A single sharp contract to lock | `/planning:interview` | The map's `interview`-typed items route here; also the graduation target |
| Product intent still fuzzy | `/planning:prd` | Graduation target when the destination is a PRD |
| Design-space item | `/planning:design`, `/event-storming:*` | `design`-typed items route here |
| Feasibility / UX unknown | `/prototype:pressure-test`, `/prototype:explore-directions` | `prototype`-typed items route here |
| External-evidence item | `/discovery:research` | `research`-typed items route here (autonomous) |
| The plan itself | `/planning:plan` | Follows `/planning:design` when the destination is a PLAN |

Pre-implementation order (blindspot → brainstorm/prototype → PRD → interview, escalating here when
it outgrows one session → reference port → design → plan → decompose): the workflow section of
`docs/finding-your-unknowns.md` in the marketplace repository.

## What this skill does NOT do

- **Does not do build work.** Build items live on the ordinary tracker (`/work-items:track add`)
  after the map graduates; a decision that resolves into buildable work is a graduation, not a
  map item.
- **Does not resolve a HITL item for the human** (inviolable). Non-interactive frontier filters
  `needs-human` items out.
- **Does not chart non-interactively.** The `chart` action refuses non-interactive sessions.
- **Does not build a map to justify its invocation.** No fog, or fits one session → route out
  (chart step 1's bail-out).
- **Does not store coordination in the memory tier.** The map lives on the tracker;
  `<memory_dir>/<slug>/` (default `.work/`) holds execution artifacts only (journals, research
  scratch, evidence).
- **Does not invent a second claim/mode mechanism.** Claims use the `work-items` plugin's claim
  model (`/work-items:track start`); mode is the `needs-human` label.

## Next

- A brand-new effort with no interview behind it: /planning:interview.
- The map is charted: /planning:wayfind work.
- The map closed: /planning:interview for a Brief destination, /planning:prd for a PRD, /planning:design ahead of the plan for a PLAN.
- Unsure where this leaves the work, or arrived mid-flow: /session-flow:workflow.

## Reference

- [`context/tracker-mechanics.md`](context/tracker-mechanics.md). The `/work-items:track` actions
  for map creation, typed-item creation, edges, frontier query, and the claim protocol
- [`context/map-anatomy.md`](context/map-anatomy.md). The map body template, the five sections,
  and the graduation/closure invariants
