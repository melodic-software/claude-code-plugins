# Map anatomy: the five sections + invariants

A map is one tracker issue (bare container-label marker, default `work-map`,
resolved per `tracker-mechanics.md`) whose sub-issues are typed
decision items. Every link in the body is an absolute URL. The issue **body** carries five sections. Everything volatile (each decision's
actual resolution, current frontier, claim state) lives on the items, not recopied into the
body. The body is a stable index, not a mirror.

## Body template

```markdown
## Destination

<One or two lines, confirmed by the user before any item existed: what finishing the map
produces. One bounded outcome, of one kind: a PRD, a set of build items, one change, a decision
record, or a general summary. This is the map's success condition.>

## Notes

- Standing constraints every session on this map must obey, one line each.
- Skills every session on this map consults, one per line (work step 5 invokes each).
- Durable pointers every session needs: PRs, committed docs, prior items, the map's dossier
  branch, external links.

<Nothing else. Background and interview facts go in the seed item's resolution
comment or the item they concern. Memory-tier `<memory_dir>/<slug>/` artifacts are
checkout-local: distill what matters there as text instead of pointing at a path other readers
cannot resolve.>

## Decisions-so-far

<A pointer INDEX: one line per resolved-in-scope decision, NOT the decisions themselves.
Each line names the item by **title**, linked to its absolute URL, and points at the
item whose resolution comment is the decision's durable home. Closed-as-out-of-scope items
do not get a line here. A map seeded from an interview has one line for its seed item, whose
resolution comment lists the interview's settled answers.>

- [<title>](<item URL>): <one-line what-was-decided> (resolved <date>)

## Not-yet-specified (fog)

<One bullet per uncertainty you cannot yet phrase as a sharp question, each opening with a short
bold label. A bullet graduates to a typed decision item only once working the map makes it
sharp. Fog is expected. An empty fog section on a young map usually means you haven't looked
hard enough.>

- **<label>**: <what is uncertain, in a line or two>

## Out-of-scope

<Explicitly excluded, decided NOT to pursue. This ledger is for **scope**, not sharpness.
Fog (cannot yet phrase the question) stays in Not-yet-specified and never graduates here.
Recording an exclusion is itself a decision; note why. A wrongly scoped existing decision item
is closed with one line here linking it; it does not get a Decisions-so-far pointer. That
index is for resolved-in-scope decisions.>
```

## Typed decision items

Each sub-issue is one topic a single session can work, holding its related **sharp** questions;
never one item per question. Its body is the question and the criteria an answer must meet,
nothing else. The `wayfind: <type>` label sets the routing target (which skill resolves it); the
body never states the type:

| Type | Meaning |
|---|---|
| `research` | An external-evidence question with no human judgment needed to resolve |
| `interview` | A contract/requirements decision the user must make |
| `design` | A design-space / domain-model decision |
| `prototype` | A feasibility (logic) or UX (ui) unknown that needs a throwaway to answer |
| `task` | Decision-unblocking do-work with no feature code and no PR tie; its resolution records what was done and the facts later items need |

Mode is materialized as the `needs-human` label (present = HITL), set only on an item that needs
the user's intent or vision, whatever its type (SKILL.md "Readiness"). Extension policy: a new
`wayfind: <type>` value requires an existing routing target. Never add a type with nowhere to go.

## Invariants (checked at every `work` session start)

1. **Every closed in-scope decision has a Decisions-so-far pointer line.** Resolved-in-comment
   but no index line → add the line. Closed-as-out-of-scope items are indexed under
   Out-of-scope instead, never under Decisions-so-far. An item closed as moot (another
   resolution invalidated its premise) carries a closing comment linking that resolution and
   no line in either index. A decision later found wrong keeps its line, rewritten as
   `[<old title>](<old URL>): superseded by [<new title>](<new URL>) (resolved <date>)`, so the index
   holds one live answer per question.
2. **No item resolved-in-comment yet still open.** In-scope resolution is atomic: comment →
   Decisions-so-far → close. A wrongly scoped item closes with one Out-of-scope line and no
   Decisions-so-far pointer (see Out-of-scope above). A dangling "resolved" comment on an
   open item is a broken close-out. Finish it.
3. **The map holds decisions, not build work.** A buildable item means the decision already
   graduated. Move it to the ordinary tracker (`/work-items:track add`, or
   `/work-items:decompose` for a plan-shaped chunk), off the map.
4. **Coordination on the tracker, files in the memory tier or on the dossier branch.**
   `<memory_dir>/<slug>/` (default `.work/`) is the memory slice (never
   committed; slug spec shared with the pipeline skills) for files one session reads; the map's
   dossier branch (SKILL.md "Shared files") holds files several sessions read. The map never
   cites a concrete `<memory_dir>/<slug>/` path; neither surface holds map state.
5. **No fog bullet that an item already charts.** Charting fog is create-then-delete; an
   interrupted run can leave the bullet behind. Delete it, and chart nothing new from it.

## Graduation and closure

- **Graduation (per resolution):** a resolved decision either sharpens the map (turns fog into
  new typed items) or feeds the destination. Fog that becomes a typed item is deleted from
  Not-yet-specified, so each uncertainty lives in one place. When it produces buildable work,
  that work leaves the map for `/work-items:track add`.
- **Sweep (per resolution):** open items whose premise the resolution invalidated are rewritten
  or closed as moot, and a closed decision it shows was wrong is superseded by a new item, per
  Work mode step 7.
- **Closure (whole map):** frontier empty ∧ every decision item closed ⟹ the destination is
  coherent. Post a closing comment that states every resolved decision in full, close the map,
  and hand those decisions to the destination's skill in a source form it accepts
  (`/planning:prd`, `/work-items:decompose #<map-number>` or `/work-items:work`, or a decision
  record or general summary; SKILL.md work step 8). Then delete the dossier branch.
