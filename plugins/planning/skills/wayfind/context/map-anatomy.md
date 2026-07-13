# Map anatomy — the five sections + invariants

A decision map is one tracker issue (bare `work-map` marker) whose sub-issues are typed
decision items. The issue **body** carries five sections. Everything volatile (each decision's
actual resolution, current frontier, claim state) lives on the items, not recopied into the
body — the body is a stable index, not a mirror.

## Body template

```markdown
## Destination

<Where this effort is going once the fog clears — the coherent Brief / PRD / PLAN it will
graduate into. One paragraph. This is the map's success condition.>

## Notes

- Pointers to `.work/<slug>/` execution artifacts, prior research, upstream context.
- Links, not recaps.

## Decisions-so-far

<A pointer INDEX, one line per resolved decision — NOT the decisions themselves. Each line
points at the item whose resolution comment is the decision's durable home.>

- #<item> — <one-line what-was-decided> (resolved <date>)

## Not-yet-specified (fog)

<Prose. The uncertainties you cannot yet phrase as sharp questions. These graduate to typed
decision items only once working the map makes them sharp. Fog is expected — an empty fog
section on a young map usually means you haven't looked hard enough.>

## Out-of-scope

<Explicitly excluded — decided NOT to pursue, distinct from fog (not-yet-phrased). Recording
an exclusion here is itself a decision; note why.>
```

## Typed decision items

Each sub-issue is one **sharp** question. The `wayfind:<type>` label sets both the routing
target (which skill resolves it) and the default mode:

| Type | Default mode | Meaning |
|---|---|---|
| `research` | autonomous-capable | An external-evidence question — no human judgment needed to resolve |
| `interview` | HITL | A contract/requirements decision the user must make |
| `design` | HITL | A design-space / domain-model decision |
| `prototype` | HITL | A feasibility (logic) or UX (ui) unknown that needs a throwaway to answer |
| `task` | per-item | Decision-unblocking do-work — no feature code, no PR tie |

Mode is materialized as the `needs-human` label (present = HITL). Extension policy: a new
`wayfind:<type>` value requires an existing routing target — never a type with nowhere to go.

## Invariants (checked at every `work` session start)

1. **Every closed decision has a Decisions-so-far pointer line.** Resolved-in-comment but no
   index line → add the line.
2. **No item resolved-in-comment yet still open.** Resolution is atomic: comment → index →
   close. A dangling "resolved" comment on an open item is a broken close-out — finish it.
3. **The map holds decisions, not build work.** A buildable item means the decision already
   graduated — move it to the ordinary tracker (`/work-items`), off the map.
4. **Coordination on the tracker, execution artifacts in `.work/`.** The map never cites a
   concrete `.work/<slug>/` path as a coordination surface; `.work/` never holds map state.

## Graduation and closure

- **Graduation (per resolution):** a resolved decision either sharpens the map (turns fog into
  new typed items) or feeds the destination. When it produces buildable work, that work leaves
  the map for `/work-items`.
- **Closure (whole map):** frontier empty ∧ every decision item closed ⟹ the destination is
  coherent. Close the map and hand the destination to the pipeline entry that fits it
  (`/planning:interview` or `/planning:prd` → Brief/PRD; `/planning:architect` → PLAN). The
  map's lifecycle ends exactly where the normal planning pipeline's begins.
