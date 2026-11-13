---
description: "Chart a too-big, still-foggy effort as a map of decision items on the work-item tracker and work its frontier one decision at a time until it closes to a PRD, decomposed work items or one work item. Use when an interview outgrew one session: 'turn this into a map', 'this is a huge foggy effort', 'I don't even know the questions yet', 'map this out', 'plan-the-plan'. New efforts start at /planning:interview, which may offer this. Already sharp tickets: /work-items."
argument-hint: "[chart|work|<item link>] [topic|map] [item]"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: interview
  summary: Chart a too-big, foggy effort as a decision map worked one decision at a time
---

**Arguments.** `[chart|work|<item link>] [topic|map] [item]`. e.g., /planning:wayfind chart <topic>, /planning:wayfind work, /planning:wayfind work <map> <item>, /planning:wayfind <item link>

## Pre-computed context

Labels: resolve them first, once per session, with the Read tool from the tracker binding,
`work-items.yaml` beside the `planning.yaml` that "Settings" reads (its `tracker` mapping; both keys
are team-only, so no personal file applies). `<prefix>` is `config.wayfind_label_prefix`, default
`wayfind:`; `<human-gated>` is `config.role_labels.human-gated`, default `needs-human`. A missing
file or key, or an empty value, means the default; any other value that is not a string is a broken
binding: name the file, key and value and stop. Every wayfind label is `<prefix>`, a space, then
its kind (`<prefix> map`, `<prefix> research`), and every label this skill writes or queries uses
those two values. Report both in one line, each with `(default)` or `(binding)`.

Open maps: list them at the start of every action with
`/work-items:track list --label '<prefix> map' --state open`, invoked via the Skill tool
([`context/tracker-mechanics.md`](context/tracker-mechanics.md)). Without the `work-items` plugin,
wayfind cannot reach the tracker: say so and stop.

## Variables

Arguments: `$ARGUMENTS`

## Purpose

For an effort **too big to hold at once AND too foggy to ticket**, where half the questions cannot
yet be phrased: turn it into a shared **map** on the work-item tracker whose children are
**decision items**, then work the map's frontier one decision at a time until its destination can
be handed onward. Say "map" and "decision item"; never "decision map". It is the escalation from an
interview that outgrew one session. The interview stays the entry for a brand-new effort
(`/planning:interview`), and may offer wayfind in its first round when the request already shows a
big, foggy effort.

**Plan, don't do.** A map holds *decisions*, not build work. Each resolved decision either sharpens
the map or feeds the destination. Nothing overrides this: no Notes line, standing preference or
item body carries execution into the map. The map lives as native tracker primitives, each
decision routes to a first-party skill, and execution artifacts live in the memory slice
`<memory_dir>/<slug>/` (default `.work/`; see
[`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md))
or, when more than one session reads them, on the map's dossier branch ("Shared files" below),
never in the map.

**Scope the map to one bounded destination** (one epic-sized outcome, never a whole product), and
chart a prototype item early wherever a cheap artifact would expose a look-or-behave question
before later decisions depend on it.

**Fidelity** is how concrete an artifact is: words and discussion, sketches or breadboards,
wireframes, prototypes, working code. Settle each decision item with the cheapest artifact that
answers its question, never below the level where it answers nothing; a prototype can cost less
than the discussion it replaces, so the cheapest answering artifact is not always the lowest. That
artifact sets the item's type (work step 5's table).

## Flow

- **Interview is the entry.** `/planning:interview` suggests wayfind once an interview passes its
  size threshold; that skill owns the threshold. An effort that fits one session skips the map.
- **Chart reads an existing interview ledger** and seeds the map from it (chart step 1). With no
  interview of the effort behind it, chart offers the interview first, preloaded with what the user
  has already said, and runs it inline.
- **The map closes to `/planning:prd`, `/planning:plan` then `/work-items:decompose`, or
  `/work-items:work`**, or ends in
  a decision record or a general summary when that is its destination (work step 8).

## Settings

Two settings, each resolved lowest layer first: the default, then the key in the repository's
`docs/conventions/planning.yaml`, read from this checkout (all keys and layers:
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md); schema:
[`${CLAUDE_PLUGIN_ROOT}/schemas/planning.schema.json`](${CLAUDE_PLUGIN_ROOT}/schemas/planning.schema.json)).
A missing file or key means the default. An invalid value is named with its file, key and value,
and the default applies. Report one line per setting naming its value and layer, e.g.
`wayfind_hitl_concurrency: 1 (default)`.

| Key | Default | Basis | Meaning |
|---|---|---|---|
| `wayfind_research_start` | `auto` | Owner decision Q532 (2026-10-15) | `auto`: start a research item without asking when research is the next step whatever the user picks (the frontier holds no item other than research items); otherwise ask first in an interactive session. `confirm`: always ask first in an interactive session |
| `wayfind_hitl_concurrency` | `1` | Owner decision Q330 (2026-11-12): one human-in-the-loop item at a time per person | The most `<human-gated>` items of one map that one person (the assignee a claim sets) may hold at once, across all of that person's sessions. Research items never count against it |

An unattended (CI) session asks no one, so labels start research there (Q532): it starts a
research item only when the item carries `<prefix> research` and no `<human-gated>`, labels chart
set while a human was present. Adding or removing those labels is how a person starts or holds one.

## The fog test (the one call that governs everything)

For every uncertainty, ask: **can I phrase it as a sharp question?**

- **Sharp** (you can state the question, even if you can't answer it yet, even if it's blocked) →
  a **decision item** on the map (a typed sub-issue).
- **Foggy** (you can't yet put words to what's uncertain) → one **labeled bullet** in the map's
  *Not-yet-specified* section, until working the map makes it sharp enough to phrase.

Sharpness, not blockedness, is the line: a blocked-but-phrasable question is a ticket; an
unblocked-but-unphrasable worry is fog.

"I don't know" is a full answer, from the user or from you. Sort each unknown by who can settle
it: evidence can → a `research` item, researched before anyone recommends an answer; only the
user can → an `interview` item; nobody can phrase it yet → fog.

## Readiness: one engine, human only for intent and vision

Mode is the `<human-gated>` label, the human-gated role label every `/work-items` skill reads, which
keeps an item off every autonomous frontier
([`context/tracker-mechanics.md`](context/tracker-mechanics.md) "Check labels"). Wayfind applies it
more narrowly than the label's general meaning: only when resolving the item needs the user's
**intent or vision**: what they want, why, or which outcome they would accept. Any other item, whatever its type, is agent-capable. Wayfind has no readiness
rules or picker of its own: the work step picks by the order below and nothing else, and map items
stay out of `/work-items:work`, whose frontier leaves out every item carrying a label that starts with `<prefix>`.

## Shared files

A map's shared work files (research findings, prototype assets, drafts that later sessions read)
go on one **dossier branch** for the map issue: `<prefix><key>-<slug>`, `<prefix>` being the
`dossier_branch_prefix` source-control setting (default `dossier/`), `<key>` the bound adapter's
`branch_ref` for the map, `<slug>` the map title in kebab-case. The first session that writes a
shared file creates it from the default branch, pushes it and links it from the map's Notes; decision
items add no branch of their own. The branch name stays keyed by the map's tracker item. Each item
writes only its own folder on it, one folder per item named `<item key>-<item slug>` the same way.
Every push to it is: fetch the branch, rebase your commit onto it, push without force; on a
rejection, fetch, rebase and push again. No force or lease is needed, because no two items write
the same folder. The branch is never merged and gets no pull request; it is deleted when the
destination's container closes, not when the map closes, and the map's closing comment names it
(work step 8). A file only one session reads stays in the memory slice.

## Refer by name, link by URL

In everything the human reads, name each item by **title**. In a chat report (chart report, work
frontier) the number may follow as a suffix; never a wall of bare `#42, #43, #44`.

Every link written to the tracker (map body, item body, comment) is the item's title linked to its
absolute URL, never a bare `#<n>`, so it resolves from any page that quotes it. Cross-references between items use real ids only, written once those
ids exist (chart step 4); a placeholder number links to an unrelated issue.

## Action Router

Parse the first token of `$ARGUMENTS`.

| Argument | Action | When |
|----------|--------|------|
| *(empty)* | **auto** | Open map exists → list its frontier by title, recommend one item and wait for the user's pick (several open maps: name them and ask which); an unattended session goes straight to `work`. No open map → propose `chart` and wait for the user's yes |
| `chart [topic]` | **Chart** | Build or extend a map, without asking first. **Interactive only**. Refuses non-interactive sessions (charting burns assumptions that need a human) |
| `work [map] [item]` | **Work** | Work one frontier item: the named one, else the first in creation order |
| An item reference (URL, `#<n>` or tracker key) | **Work** | Work that item on its map. A reference to a map itself (it carries `<prefix> map`) is handled as *(empty)* for that map |
| Any other text | **auto** | The text is the topic: an open map for it → as *(empty)*. Else propose `chart` with the topic and wait for the user's yes |

## Chart mode

Charting needs a human in the loop, and a session cannot detect that on its own, so the caller
declares it (the same rule `/planning:interview` applies): when the invocation says the run is
unattended (a loop, a spawned worker, a `claude -p` run, another skill's chain), STOP and report
that charting needs an interactive session. Do not fabricate a map.

1. **Survey, interview, fog test.** Read the repository's glossary and work-item conventions
   first, when it has them, so questions use its terms and items follow its tracker rules (the
   glossary is found the way `/planning:interview`'s survey finds it). Then ground in the effort
   (any existing `<memory_dir>/<slug>/`, recent commits, the topic).
   - **Seed from the interview:** when the slice holds an interview ledger
     (`interview-checklist.md`), its settled answers become one seed decision item, created with
     the others in step 4, whose resolution comment lists them; close it at once with one
     *Decisions-so-far* pointer (the work-mode step 6 sequence). Its open, deferred and blocked questions become candidate
     decision items. The constraints every later session must obey go into *Notes*, one line
     each; its self-answered facts, `## Starting point` line and session-shorthand glossary go
     in the seed item's resolution comment, as text, never as a path, so nothing the interview
     already asked is asked again.
   - Sort every remaining uncertainty through the fog test: sharp → candidate decision item;
     foggy → a *Not-yet-specified* bullet. Tell the user once that "I don't know" is a full
     answer.
   - **Set ready questions aside.** A sharp question that already has a recommendation and
     waits on no other decision is not map material: hold it for the one round step 2 asks.
     Only what stays open after that round becomes an item.
   - **No-fog bail-out:** if the survey leaves *both* halves of the trigger unmet (every
     uncertainty is already sharp, or the whole effort fits one session), the effort skips the
     map. STOP and route out instead of fabricating one: a single contract to lock → invoke
     `/planning:interview` via the Skill tool; a set of sharp tickets → `/work-items:decompose`
     (or `/work-items:track add` for one ticket); small enough to just do → say so. The trigger
     is too-big AND foggy, both, never either alone. Seeded rows are sharp by construction, so
     the fog must come from the survey; a seeded interview with no fog goes back to its own
     handoff and resume.
   - **No interview yet:** only once the bail-out has not fired, when neither the slice nor this
     conversation holds an interview of the effort, offer to run it first, preloaded with what the
     user has said (the topic, stated constraints, any starting point). On yes, invoke
     `/planning:interview` via the Skill tool with that preload and continue from its ledger once
     it hands off. On no, chart only if the user still asks for a map.
2. **Ask what done looks like, then propose the whole map.** Nothing is created on the tracker
   before the second yes.
   - **Destination.** Chart's first question to the user is what finishing the map produces,
     confirmed as one or two lines. Its kind sets the closure target (work step 8): a PRD, a
     set of build items to decompose, one change, a decision record, or a general summary.
     Recommend a PRD for a coding effort, and a decision record or summary for one that is not.
     Narrow it to one bounded destination when it reads like a whole product. Put this question
     to the user in the first message that asks them anything, step 1's interview offer
     included; saying that creation waits for a destination does not ask it.
   - **Ready questions.** Next, ask every question step 1 set aside in one
     `/planning:interview` round. The answers join the seed item's settled answers; with no
     interview ledger, the seed item is still created to hold them (step 1's close-at-once
     sequence).
   - **Proposed map.** Show the map as it would be created and wait for one yes: the
     Destination; each item to create with its title, type, mode and what it waits on; the
     Not-yet-specified bullets; the Out-of-scope list. Apply the changes the user asks for and
     show it again. Extending an existing map, show only what would be added.
3. **Create or extend the map issue.** On first use in a repo, **verify** the wayfind label
   taxonomy (`<prefix> *`, `<human-gated>`; snippet in `context/tracker-mechanics.md`) is present:
   an unknown `--label` fails the create. Honor
   the consuming repository's declared label ownership: if it names a label-as-code source of
   truth, STOP and report the exact missing set to that owner; otherwise report the set and ask
   the user how labels are provisioned. Never create labels ad hoc from this skill. Then create
   one issue labeled `<prefix> map` (+ any repo program labels). Its body carries
   five sections:
   - **Destination**: the confirmed destination from step 2.
   - **Notes**: only what every session on this map must obey or consult: standing
     constraints, one line each; the skills to consult; durable pointers (PRs, committed docs,
     prior items, the dossier branch, external links). Background and interview facts go in the
     seed item's resolution comment or the item they concern. Memory-tier
     `<memory_dir>/` artifacts are checkout-local, so distill their relevant content there as
     text instead of pointing at paths other readers cannot resolve.
   - **Decisions-so-far**: a *pointer index* of resolved-in-scope decisions. Each home is its own
     item's resolution comment, never recopied here; wrongly scoped closures get no pointer.
   - **Not-yet-specified**: fog, one bullet per uncertainty, each opening with a short bold
     label. Fog never moves into Out-of-scope for being unphrasable, only by an explicit scope
     ruling at closure (work step 8).
   - **Out-of-scope**: scope exclusions, not unphraseable fog.

   Template and tracker actions: [`context/tracker-mechanics.md`](context/tracker-mechanics.md).
4. **Create typed decision items, then wire them.** Create one sub-issue of the map per topic
   one session can work (state no token figure), its related sharp questions grouped inside it,
   never one item per question. An item body holds the question and the criteria an answer must
   meet, nothing else, except a prototype item, whose body follows the prototype template
   ([`context/map-anatomy.md`](context/map-anatomy.md) "Prototype item body"). The type label sets the
   routing target (the type table in work step 5). Then, in a second pass once every item has
   its real id, wire `blocked-by` edges and write any cross-reference between items. Wire an edge
   only where one decision genuinely gates another; never invent edges to impose order.
5. **Materialize the mode** on each item at creation: `<human-gated>` only for an intent or vision
   question ("Readiness" above), whatever the type. The label's presence or absence is the only
   mode mechanism; no `Mode:` body field.
6. **Hand off to `work`.** Report the frontier (open, unblocked, unassigned items) **by title**,
   number as a link or suffix, and recommend `/planning:wayfind work`. Start or offer the
   frontier's research items per `wayfind_research_start` ("Settings"), in parallel (work step
   4's research exception); their resolutions often sharpen the remaining fog before the first
   HITL session.

## Work mode

1. **Session-start reclaim + map hygiene.** Reclaim any of your own stale in-progress items
   (idempotent). Check the map's invariants: every closed **in-scope** decision has a
   *Decisions-so-far* pointer line (closed-as-out-of-scope items have an Out-of-scope line
   instead; closed-as-moot items have only their closing comment); no item resolved-in-comment
   but still open; no Not-yet-specified bullet that an item already charts (delete it). Fix
   violations before proceeding.
2. **Load the map at low resolution.** Read the map body, its child list and the seed item's
   resolution comment when the map has one (it holds the settled answers and facts, so none is
   asked again); open an item's body
   only when the step at hand needs it (the picked item, a blocker, a decision the sweep checks).
3. **Compute the frontier.** `frontier = open ∧ zero OPEN blockers ∧ unassigned` (count open
   blockers, not the raw edge count), in creation order. In a non-interactive session, filter OUT
   `<human-gated>` items; if that empties the frontier, STOP with a truthful "all remaining decisions
   need a human". Never resolve a HITL item by standing in for the human.
4. **Pick one and claim it.** Take the item the user named, else the first frontier item in
   creation order. A `<human-gated>` item is skipped while the person this session claims as (its
   assignee) already holds `wayfind_hitl_concurrency` claimed `<human-gated>` items on the map
   ("Settings"); other people's claims do not count; with nothing else left,
   report which items hold the slots and stop. A named item that is off the frontier, or a named
   `<human-gated>` item while the slots are full, is reported with the reason and not claimed. Claim through `/work-items:track start` (the sibling
   claim model: assignee + lease with a race-safe back-off, no claim label; see
   [`context/tracker-mechanics.md`](context/tracker-mechanics.md)). One item per session, with one
   exception: **`research`-typed items may be burned down in parallel**, started per
   `wayfind_research_start`. When the frontier holds several, claim each individually (same
   protocol, one claim per item) and dispatch `/discovery:research` per item (it already runs in a
   fresh-context subagent). Ask `/discovery:research` for its lightest verification level,
   `light`, with no separate verifier pass. Only the repository sets that level; when it resolves
   to `standard`, skip the verifier for cost as `/discovery:research` allows, and under `strict`
   let the verifier run. Graduate each on completion per step 6; the resolution comment is the
   finding's durable home, and the findings file and its sidecars are copied to the item's folder
   on the dossier branch first ([`context/tracker-mechanics.md`](context/tracker-mechanics.md)
   "Graduate a research item"). Never fan out a `<human-gated>` item.
5. **Consult the Notes skills, then route by type.** First invoke each skill the map's Notes lists
   for every session, one Skill call per skill. Then invoke the target skill for the item's type
   label (never a type its body states); its own Q&A supplies the HITL loop:

   | Type label | Usually | Routes to |
   |---|---|---|
   | `<prefix> research` | agent-capable | `/discovery:research` (falls back to inline research if not enabled) |
   | `<prefix> interview` | `<human-gated>` (intent) | `/planning:interview` |
   | `<prefix> design` | agent-capable unless it asks for vision | `/planning:design`, or, when enabled, `/event-storming:methodology` / `/event-storming:simulation` when the item is domain/event-model work |
   | `<prefix> prototype` | `<human-gated>` when the user judges it | `/prototype:pressure-test` (behaviour/feasibility) or `/prototype:explore-directions` (design/UX), falling back to an inline prototype if not enabled. The item body says which. Its files go in the item's folder on the dossier branch ("Shared files"); its verdict goes in the resolution comment |
   | `<prefix> task` | per item | Direct decision-unblocking work. No feature code, no PR tie. Its resolution records what was done and the facts later items need. Work only a human can do (a vendor sign-up, credentials, a dashboard) routes to `/wizard:generate`; its resolution records the names and locations of what was set up, never the values |

6. **Graduate on every resolution.** Every edit to the map body, here or anywhere in this skill,
   applies its change to a copy of the body read right before the write, then reads the body back:
   if the change is missing (another session wrote in between), apply it to that copy and write
   again.
   Resolved **in scope**: post the resolution as a comment on
   the item, add its one-line pointer (title linked by URL) to *Decisions-so-far*, then close
   the item (comment → index → close, as one atomic sequence). The comment takes its type's shape
   ([`context/map-anatomy.md`](context/map-anatomy.md) "Resolution comments"). A decision that
   rests on a prototype not yet run is recorded as provisional, naming that prototype item, and
   that prototype's resolution confirms or reverses it (map-anatomy "Provisional decisions").
   **Wrongly scoped** (on the tracker
   but not this effort): add one Out-of-scope line linking it, then close it, with no
   Decisions-so-far pointer. Fog stays in Not-yet-specified and never moves into Out-of-scope for
   being unphrasable, only by an explicit scope ruling at closure (step 8). If the resolution sharpened previously-foggy uncertainty, chart the new sharp
   items now (create, then wire, as chart step 4) and delete that bullet from Not-yet-specified.
7. **Sweep the map after every resolution.** Reread the open items and closed decisions against
   what was just decided:
   - An open item whose premise the resolution invalidated: rewrite its question if one still
     stands, then reset its type label, mode label and blocked-by edges as chart steps 4-5
     require; otherwise close it as not planned with a comment linking the resolution that made
     it moot. A moot item gets no line in either index.
   - A closed decision the resolution shows was wrong: open a new decision item that links the
     old one, with its type and mode labels set as chart steps 4-5 require, and work it like any
     other. When it resolves, add its pointer to Decisions-so-far and change the old decision's
     line to `[<old title>](<old URL>): superseded by [<new title>](<new URL>) (resolved <date>)`.
     Never reopen the old item or edit its resolution comment.

   **Report the item.** Then report the closed item, its new Decisions-so-far line, the items
   charted from it and what it unblocked. When the frontier still holds an item, end with one line,
   since the map holds the state: clear, then `/planning:wayfind <next item URL>`, the next
   item being the first frontier item in creation order. With an empty frontier, go to step 8.
8. **Map closure → destination handoff.** When the frontier holds no item and every decision item
   is closed, empty Not-yet-specified first; the map does not close while it holds a bullet. Each
   bullet is charted (chart step 4), moved into a mop-up `interview` item that closure offers, or
   ruled out of scope by the user, which moves it to Out-of-scope with the reason; that ruling is
   the one way fog leaves without being charted. Then post a closing comment on the map that states every resolved decision in full: for
   each Decisions-so-far line, its title and Q/D id (when it has one) and the decision its
   resolution comment records, not only the link, and names the dossier branch when one exists. Then close the map issue and hand the decisions
   to the destination's skill in a source form it accepts:

   | Destination | Closes to |
   |---|---|
   | A PRD | `/planning:prd`, with the closing comment's decisions as its task description |
   | A set of build items (a spec or plan) | `/planning:plan`, with the closing comment's decisions as its task description, then `/work-items:decompose` from that plan. A map whose decisions already read as slices goes straight to `/work-items:decompose #<map-number>`; its item source reads the map's body and comments, so it finds the decisions in the closing comment |
   | One change | `/work-items:work` on the item `/work-items:track add` files for it, its body carrying the decisions |
   | A decision record | `/architecture:record-decision` when enabled, else the repository's ADR convention, given the decisions |
   | A general summary | The closing comment is the summary; no further skill |

   Keep the map's dossier branch, if one exists, until the destination's container closes, then
   delete it.

## Escalation. Pull the user back to charting at choke points

`/planning:wayfind`'s description carries the proactive trigger. The sibling skills carry
**pull-back lines**: when `/planning:interview`, `/planning:plan`, or `/implementation:implement`
hits a task that is clearly too-big-AND-foggy for their stage, they name `/planning:wayfind` as the escalation, **guiding the
user, never auto-switching**. Their pull-back wording lives in each of those skills; this skill
owns the trigger's meaning (too-big + fog, both, not either alone).

## Composition

| When | Skill | How it composes |
|---|---|---|
| Effort too big AND foggy to ticket | **`/planning:wayfind`** (this) | Produces a map of decision items; closes to its destination |
| The entry, and a single sharp contract to lock | `/planning:interview` | Suggests wayfind past its size threshold; chart runs it inline when no interview exists; `interview`-typed items route here |
| Product intent still fuzzy | `/planning:prd` | Closure target when the destination is a PRD |
| Sharp build work | `/planning:plan`, `/work-items:decompose`, `/work-items:work` | Closure targets for a set of build items (plan, then decompose) or one change |
| Human-only setup in a task item | `/wizard:generate` | `task`-typed items whose work only a human can do route here |
| Design-space item | `/planning:design`, `/event-storming:*` | `design`-typed items route here |
| Feasibility / UX unknown | `/prototype:pressure-test`, `/prototype:explore-directions` | `prototype`-typed items route here |
| External-evidence item | `/discovery:research` | `research`-typed items route here |

Pre-implementation order (blindspot → brainstorm/prototype → interview, calling a PRD when product
intent is unsettled and escalating here when it outgrows one session → reference port → design → plan → decompose): the workflow section of
`docs/finding-your-unknowns.md` in the marketplace repository.

## What this skill does NOT do

- **Does not do build work.** Build items live on the ordinary tracker (`/work-items:track add`)
  after the map closes; a decision that resolves into buildable work is a graduation, not a map
  item. No Notes line overrides this.
- **Does not resolve a HITL item for the human** (inviolable). Non-interactive frontier filters
  `<human-gated>` items out.
- **Does not chart non-interactively.** The `chart` action refuses non-interactive sessions.
- **Does not build a map to justify its invocation.** No fog, or fits one session → route out
  (chart step 1's bail-out).
- **Does not store coordination in the memory tier or on the dossier branch.** The map lives on
  the tracker; the memory slice and the dossier branch hold files only.
- **Does not invent a second claim, mode or picking mechanism.** Claims use the `work-items`
  plugin's claim model (`/work-items:track start`); mode is the `<human-gated>` label; the pick is
  the named item or creation order.

## Next

- The map is charted: /planning:wayfind work.
- The effort has no interview behind it yet: /planning:interview.
- The map closed on a set of build items: /planning:plan.
- The map closed on build items whose decisions already read as slices: /work-items:decompose #<map-number>.
- The map closed on a PRD: /planning:prd.

## Reference

- [`context/tracker-mechanics.md`](context/tracker-mechanics.md). The `/work-items:track` actions
  for map creation, typed-item creation, edges, frontier query, and the claim protocol
- [`context/map-anatomy.md`](context/map-anatomy.md). The map body template, the five sections,
  and the graduation/closure invariants
