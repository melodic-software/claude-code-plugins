---
name: wayfind
description: "Chart a too-big, still-foggy effort as a shared decision map on the work-item tracker, then work its frontier one decision at a time — routing each resolved decision to the right skill until the map graduates to a Brief / PRD / PLAN. Use when a task is too big to hold at once AND parts are still too fuzzy to phrase as sharp tickets ('this is a huge foggy effort', 'I don't even know the questions yet', 'map this out', 'chart this program', 'plan-the-plan'); skip when the work is already a set of sharp, answerable tickets (use /planning:interview or /work-items) or small enough to just do."
argument-hint: "[chart|work] [topic] (e.g., /planning:wayfind chart <topic>, /planning:wayfind work)"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(gh issue list*)"
  - "Bash(gh issue view*)"
  - "Bash(gh api user*)"
  - "Bash(gh label list*)"
---

## Pre-computed context

Current user: !`gh api user --jq '.login' 2>/dev/null || echo "unknown"`
Open maps: !`gh issue list --label work-map --state open --json number,title --jq '.[] | "#\(.number) \(.title)"' 2>/dev/null || echo "none"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Some efforts are **too big to hold at once AND too foggy to ticket** — you can't yet
phrase half the questions, let alone answer them. `/interview` needs a coherent task;
`/architect` needs a coherent plan; both presuppose you already know what you're deciding.
`/wayfind` sits **upstream of all of them**: it turns a too-big-foggy effort into a shared
**decision map** on the work-item tracker, then works that map's frontier one decision at a
time until the fog burns off and a real destination (Brief / PRD / PLAN) can be handed onward.

**Plan, don't do.** A map holds *decisions*, not build work. Each decision item, once
resolved, either sharpens the map or graduates to the destination. The moment the destination
is coherent, the map closes and the normal pipeline (`/interview → /design → /architect →
/implement`) takes over. Fog-of-war framing adapted from Matt Pocock's wayfinder — this skill
diverges by persisting the map as native tracker primitives, routing each decision to a
first-party skill, and keeping execution artifacts in `.work/` rather than the map.

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
unblocked-but-unphrasable worry is fog. *(Ticket-vs-fog distinction: Pocock's wayfinder.)*

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

1. **Survey + fog test.** Ground in the effort (read any existing `.work/<slug>/`, recent
   commits, the topic). Sort every uncertainty through the fog test: sharp → candidate
   decision item; foggy → *Not-yet-specified* prose.
2. **Create or extend the map issue.** On first use in a repo, bootstrap the wayfind label
   taxonomy (`work-map`, `wayfind:*`, `needs-human`) create-if-missing — a fresh repo won't have
   them and an unknown `--label` fails the create. Then create one issue labelled bare `work-map`
   (+ any repo program labels). Body carries the five sections — **Destination** (where this is going once the
   fog clears) / **Notes** (pointers to `.work/` artifacts, research, prior context) /
   **Decisions-so-far** (a *pointer index* — each resolved decision's home is its own item's
   resolution comment, never recopied here) / **Not-yet-specified** (fog, prose) /
   **Out-of-scope**. Template + exact `gh` calls: [`context/tracker-mechanics.md`](context/tracker-mechanics.md).
3. **Create typed decision items** as sub-issues of the map, one per sharp question. Type
   label sets the routing target and the default mode (below). Wire `blocked-by` edges where
   one decision genuinely gates another — never invent edges to impose false order.
4. **Materialize the mode** on each item at creation: HITL types (`interview`, `design`,
   `prototype`) get the `needs-human` label; `research` omits it (autonomous-capable); `task`
   is per-item. One mechanism — the presence/absence of `needs-human` — carries the mode; no
   parallel `Mode:` body field.
5. **Hand off to `work`.** Report the frontier (open, unblocked, unassigned items) and
   recommend `/planning:wayfind work` to start resolving.

## Work mode

1. **Session-start reclaim + map hygiene.** Reclaim any of your own stale in-progress items
   (idempotent). Check the map's invariants: every closed decision has a *Decisions-so-far*
   pointer line; no item resolved-in-comment but still open. Fix violations before proceeding.
2. **Compute the frontier.** `frontier = open ∧ zero OPEN blockers ∧ unassigned` (a *closed*
   blocker no longer holds an item back — count open blockers, not the raw edge count). In a
   non-interactive session, further filter OUT `needs-human` items; if that empties the
   frontier, STOP with a truthful "all remaining decisions need a human" — never resolve a
   HITL item by standing in for the human.
3. **Pick one and claim it** (sibling claim model — `status:claimed` label + `@me` assignee +
   comment-ID collision check; see [`context/tracker-mechanics.md`](context/tracker-mechanics.md)).
4. **Route by type** — invoke the target skill directly; its own Q&A supplies the HITL loop:

   | Type label | Mode | Routes to |
   |---|---|---|
   | `wayfind:research` | autonomous-capable | `/discovery:research` (falls back to inline research if not installed) |
   | `wayfind:interview` | HITL | `/planning:interview` |
   | `wayfind:design` | HITL | `/planning:design` — or `/event-storming:methodology` / `/event-storming:simulation` when the item is domain/event-model work |
   | `wayfind:prototype` | HITL | `/prototype:logic` (behaviour/feasibility) or `/prototype:ui` (design/UX) — the item body says which |
   | `wayfind:task` | per-item | Direct decision-unblocking work — no feature code, no PR tie |

5. **Graduate on every resolution.** When the decision resolves: post the resolution as a
   comment on the item, add its one-line pointer to the map's *Decisions-so-far* index, then
   close the item (comment → index → close, as one atomic sequence). If the resolution
   sharpened previously-foggy uncertainty, chart the new sharp items now.
6. **Map closure → destination handoff.** When the frontier is empty and every decision item
   is closed, the destination is coherent: close the map issue and hand the destination
   onward (`/planning:interview` or `/planning:prd` for a Brief/PRD; `/planning:architect`
   for a PLAN). A map's job ends where the pipeline's begins.

## Escalation — pull the user back to charting at choke points

`/wayfind`'s description carries the proactive trigger. The sibling skills carry **pull-back
lines**: when `/interview`, `/architect`, or `/implement` hits a task that is clearly
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
| Feasibility / UX unknown | `/prototype:logic`, `/prototype:ui` | `prototype`-typed items route here |
| External-evidence item | `/discovery:research` | `research`-typed items route here (autonomous) |
| The plan itself | `/planning:architect` | Graduation target when the destination is a PLAN |

## What this skill does NOT do

- **Does not do build work.** A map holds decisions; build items live on the ordinary tracker
  (`/work-items`) after the map graduates. If a decision resolves into buildable work, that's
  a graduation, not a map item.
- **Does not resolve a HITL item for the human.** `needs-human` items are never resolved by
  an agent standing in for the user (inviolable). Non-interactive frontier filters them out.
- **Does not chart non-interactively.** Charting burns assumptions that need a human in the
  loop; the `chart` action refuses non-interactive sessions.
- **Does not store coordination in `.work/`.** The map (coordination) lives on the tracker;
  `.work/<slug>/` holds execution artifacts only (journals, research scratch, evidence).
- **Does not invent a second claim/mode mechanism.** Claims use the sibling `/work-items`
  model; mode is the `needs-human` label — no parallel taxonomy.

## Reference

- [`context/tracker-mechanics.md`](context/tracker-mechanics.md) — the `gh` commands for map
  creation, typed-item creation, edges, frontier query, and the claim protocol
- [`context/map-anatomy.md`](context/map-anatomy.md) — the map body template, the five
  sections, and the graduation/closure invariants
