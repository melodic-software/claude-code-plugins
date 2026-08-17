---
description: "Chart a too-big, still-foggy effort as a shared decision map on the work-item tracker, then work its frontier one decision at a time — routing each resolved decision to the right skill until the map graduates to a Brief / PRD / PLAN. Use when a task is too big to hold at once AND parts are still too fuzzy to phrase as sharp tickets ('this is a huge foggy effort', 'I don't even know the questions yet', 'map this out', 'chart this program', 'plan-the-plan'); skip when the work is already a set of sharp, answerable tickets (use /planning:interview or /work-items) or small enough to just do."
argument-hint: "[chart|work] [topic] (e.g., /planning:wayfind chart <topic>, /planning:wayfind work)"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(gh issue list*)"
  - "Bash(gh issue view*)"
  - "Bash(gh api user*)"
  - "Bash(gh label list*)"
shell: bash
metadata:
  workflow-stage: contract
  summary: Chart a too-big, foggy effort as a decision map worked one decision at a time
---

## Pre-computed context

Current user: !`gh api user --jq '.login' 2>/dev/null || echo "unknown"`
Open maps: !`gh issue list --label work-map --state open --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || echo "none"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Some efforts are **too big to hold at once AND too foggy to ticket** — you can't yet
phrase half the questions, let alone answer them. `/planning:interview` needs a coherent task;
`/planning:plan` needs a coherent plan; both presuppose you already know what you're deciding.
`/planning:wayfind` sits **upstream of all of them**: it turns a too-big-foggy effort into a shared
**decision map** on the work-item tracker, then works that map's frontier one decision at a
time until the fog burns off and a real destination (Brief / PRD / PLAN) can be handed onward.

**Plan, don't do.** A map holds *decisions*, not build work. Each decision item, once
resolved, either sharpens the map or graduates to the destination. The moment the destination
is coherent, the map closes and the normal pipeline (`/planning:interview → /planning:design → /planning:plan →
/implementation:implement`) takes over. The map persists as native tracker primitives, each decision routes
to a first-party skill, and execution artifacts live in `<memory_dir>/<slug>/` (default
`.work/`) — the topic-docs convention's memory tier, slug spec and all (see
[`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md))
— never in the map itself.

**Two modes.** `chart` builds or extends a map (interactive only). `work` picks one item off
the map's frontier and drives it to resolution. The default action auto-detects: an existing
open map for the topic → `work`; nothing yet → `chart`.

## The fog test (the one call that governs everything)

For every uncertainty, ask: **can I phrase it as a sharp question?**

- **Sharp** (you can state the question, even if you can't answer it yet, even if it's
  blocked) → it's a **decision item** on the map (a typed sub-issue).
- **Foggy** (you can't yet put words to what's uncertain) → it stays **prose** in the map's
  *Not-yet-specified* section. It graduates to a typed item only once working the map has
  made it sharp enough to phrase.

Sharpness, not blockedness, is the line. A blocked-but-phrasable question is a ticket; an
unblocked-but-unphrasable worry is fog.

## Refer by name

In everything the human reads — chart report, work-mode frontier, map-body index lines —
name each item by **title**, with the number as a link or suffix. Never a wall of bare
`#42, #43, #44`. Pre-computed context already prints `"#<number> <title>"`; keep both
halves.

## Action Router

Parse the first token of `$ARGUMENTS`.

| Argument | Action | When |
|----------|--------|------|
| *(empty)* | **auto** | Open map for the topic exists → `work`; else → `chart` |
| `chart [topic]` | **Chart** | Build or extend a decision map. **Interactive only** — refuses non-interactive sessions (charting burns assumptions that need a human) |
| `work [#map]` | **Work** | Pick one frontier item and drive it to resolution |

## Chart mode

Charting is a human-in-the-loop session. If the session is non-interactive
(`CLAUDE_CODE_REMOTE`, `claude -p`, an autonomous loop), STOP and report that charting needs
an interactive session — do not fabricate a map.

1. **Survey + fog test.** Ground in the effort (read any existing `<memory_dir>/<slug>/`, recent
   commits, the topic). Sort every uncertainty through the fog test: sharp → candidate
   decision item; foggy → *Not-yet-specified* prose. **No-fog bail-out:** if the survey
   leaves *both* halves of the trigger unmet — every uncertainty is already sharp, or the
   whole effort fits one session — this effort does not need a map. STOP and route out
   instead of fabricating one: a single contract to lock → `/planning:interview`; a set of
   sharp tickets → `/work-items`; small enough to just do → say so. (The trigger is too-big
   AND foggy — both, never either alone.)
2. **Create or extend the map issue.** On first use in a repo, **verify** the wayfind label
   taxonomy (`work-map`, `wayfind: *`, `needs-human`) is present — an unknown `--label` fails the
   create. Honor the consuming repository's declared label ownership. If it names a label-as-code
   source of truth, STOP and report the exact missing set to that owner; otherwise report the set and
   ask the user how labels are provisioned. Never create labels ad hoc from this skill. Then create one issue labelled bare `work-map`
   (+ any repo program labels). Body carries the five sections — **Destination** (where this is going once the
   fog clears) / **Notes** (durable pointers only — PRs, committed docs, prior items, external links;
   memory-tier `<memory_dir>/` artifacts are checkout-local, so distill their relevant content inline
   instead of pointing at paths other readers cannot resolve) /
   **Decisions-so-far** (a *pointer index* of resolved-in-scope decisions — each home is its
   own item's resolution comment, never recopied here; mis-scoped closures do not get a
   pointer) / **Not-yet-specified** (fog, prose — fog never graduates into Out-of-scope) /
   **Out-of-scope** (scope exclusions, not unphraseable fog). Template + exact `gh` calls:
   [`context/tracker-mechanics.md`](context/tracker-mechanics.md).
3. **Create typed decision items** as sub-issues of the map, one per sharp question. Type
   label sets the routing target and the default mode (below). Wire `blocked-by` edges where
   one decision genuinely gates another — never invent edges to impose false order.
4. **Materialize the mode** on each item at creation: HITL types (`interview`, `design`,
   `prototype`) get the `needs-human` label; `research` omits it (autonomous-capable); `task`
   is per-item. One mechanism — the presence/absence of `needs-human` — carries the mode; no
   parallel `Mode:` body field.
5. **Hand off to `work`.** Report the frontier (open, unblocked, unassigned items) **by
   title**, number as a link or suffix, and recommend `/planning:wayfind work` to start
   resolving. If the fresh frontier holds
   `research`-typed items, offer to fire them now in parallel (work mode's research
   exception) — their resolutions often sharpen the remaining fog before the first HITL
   session.

## Work mode

1. **Session-start reclaim + map hygiene.** Reclaim any of your own stale in-progress items
   (idempotent). Check the map's invariants: every closed **in-scope** decision has a
   *Decisions-so-far* pointer line (closed-as-out-of-scope items have an Out-of-scope line
   instead, not a pointer); no item resolved-in-comment but still open. Fix violations
   before proceeding.
2. **Compute the frontier.** `frontier = open ∧ zero OPEN blockers ∧ unassigned` (a *closed*
   blocker no longer holds an item back — count open blockers, not the raw edge count). In a
   non-interactive session, further filter OUT `needs-human` items; if that empties the
   frontier, STOP with a truthful "all remaining decisions need a human" — never resolve a
   HITL item by standing in for the human.
3. **Pick one and claim it** (sibling claim model — `@me` assignee + claim-comment lease with
   comment-order collision check, no claim label; see [`context/tracker-mechanics.md`](context/tracker-mechanics.md)).
   One item per session — with one exception: **`research`-typed items may be burned down in
   parallel.** They are autonomous-capable by construction, so when the frontier holds
   several, claim each one individually (same protocol, one claim per item) and dispatch
   `/discovery:research` per item — it already runs in a fresh-context subagent. Graduate
   each on completion per step 5; the resolution comment is the finding's durable home,
   research scratch stays in `<memory_dir>/<slug>/`. Never fan out a `needs-human` item.
4. **Route by type** — invoke the target skill directly; its own Q&A supplies the HITL loop:

   | Type label | Mode | Routes to |
   |---|---|---|
   | `wayfind: research` | autonomous-capable | `/discovery:research` (falls back to inline research if not installed) |
   | `wayfind: interview` | HITL | `/planning:interview` |
   | `wayfind: design` | HITL | `/planning:design` — or `/event-storming:methodology` / `/event-storming:simulation` when the item is domain/event-model work |
   | `wayfind: prototype` | HITL | `/prototype:pressure-test` (behaviour/feasibility) or `/prototype:explore-directions` (design/UX) — the item body says which |
   | `wayfind: task` | per-item | Direct decision-unblocking work — no feature code, no PR tie |

5. **Graduate on every resolution.** When the decision resolves **in scope**: post the
   resolution as a comment on the item, add its one-line pointer (title, number as suffix)
   to the map's *Decisions-so-far* index, then close the item (comment → index → close, as
   one atomic sequence). If the item is **mis-scoped** (on the tracker but not this effort):
   close it and add one Out-of-scope line linking it — it does **not** get a Decisions-so-far
   pointer. Fog stays in Not-yet-specified and never graduates into Out-of-scope. If the
   resolution sharpened previously-foggy uncertainty, chart the new sharp items now.
6. **Map closure → destination handoff.** When the frontier is empty and every decision item
   is closed, the destination is coherent: close the map issue and hand the destination
   onward (`/planning:interview` or `/planning:prd` for a Brief/PRD; `/planning:plan`
   for a PLAN). A map's job ends where the pipeline's begins.

## Escalation — pull the user back to charting at choke points

`/planning:wayfind`'s description carries the proactive trigger. The sibling skills carry **pull-back
lines**: when `/planning:interview`, `/planning:plan`, or `/implementation:implement` hits a task that is clearly
too-big-AND-foggy for their stage, they name `/planning:wayfind` as the better entry —
**guiding the user, never auto-switching**. Wording lives in each of those skills; this skill
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
| The plan itself | `/planning:plan` | Graduation target when the destination is a PLAN |

## What this skill does NOT do

- **Does not do build work.** A map holds decisions; build items live on the ordinary tracker
  (`/work-items`) after the map graduates. If a decision resolves into buildable work, that's
  a graduation, not a map item.
- **Does not resolve a HITL item for the human.** `needs-human` items are never resolved by
  an agent standing in for the user (inviolable). Non-interactive frontier filters them out.
- **Does not chart non-interactively.** Charting burns assumptions that need a human in the
  loop; the `chart` action refuses non-interactive sessions.
- **Does not build a map to justify its invocation.** No fog, or fits one session → route
  out (chart step 1's bail-out).
- **Does not store coordination in the memory tier.** The map (coordination) lives on the
  tracker; `<memory_dir>/<slug>/` (default `.work/`) holds execution artifacts only (journals,
  research scratch, evidence).
- **Does not invent a second claim/mode mechanism.** Claims use the sibling `/work-items`
  model; mode is the `needs-human` label — no parallel taxonomy.

## Reference

- [`context/tracker-mechanics.md`](context/tracker-mechanics.md) — the `gh` commands for map
  creation, typed-item creation, edges, frontier query, and the claim protocol
- [`context/map-anatomy.md`](context/map-anatomy.md) — the map body template, the five
  sections, and the graduation/closure invariants
