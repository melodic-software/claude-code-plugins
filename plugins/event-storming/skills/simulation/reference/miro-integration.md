# Miro Integration for Digital EventStorming

This reference covers how to use Miro as a digital canvas for EventStorming workshops, including agentic simulation. All Miro-specific details are isolated here — the rest of the skill is tool-agnostic.

---

## Miro board access via the `miro` plugin

The live-board path uses the first-party **`miro` plugin** — a bundled local-stdio MCP server that
exposes the full board lifecycle (create → populate → delete-teardown) plus connectors, frames,
tags, and overlap detection. It is a **separate plugin from `event-storming`**: markdown is the
default output, and the board capability is opt-in, so enabling `event-storming` does not start a
Miro MCP server.

> **Remote-MCP trust (resolved).** Miro's official hosted server (`mcp.miro.com`, remote HTTP,
> OAuth 2.1) was **rejected** as the live-board target: it has no board-delete tool (the skill's
> teardown cannot be expressed on it) and would delegate board/workshop content egress to a
> third-party remote MCP. The live-board path targets the first-party bundled server instead
> (owner's own code, local stdio, no third-party remote egress). Durable accept record + rationale:
> the marketplace repo's MCP decision table in `docs/MIGRATION-PLAYBOOK.md` — not restated here.

### Tool namespace

Because the server is plugin-bundled, its tools are namespaced at runtime as
**`mcp__plugin_miro_miro__<tool>`** (e.g. `mcp__plugin_miro_miro__miro_create_board`). A bare
`miro_*` name — or a bare-server-key `mcp__miro__…` — does **not** resolve for a plugin-bundled
server. Every `miro_*` tool named in this skill and its reference docs denotes that plugin's tool
under the `mcp__plugin_miro_miro__` prefix; the availability gate (SKILL.md "Miro availability &
graceful degradation") probes the prefixed form.

### Setup

A fresh consumer has only `event-storming` installed — the `miro` plugin must be **installed from the
marketplace first, then enabled** (enabling alone does not install it).

1. **Add the marketplace** (if not already added): `claude plugin marketplace add melodic-software/claude-code-plugins`.
2. **Install the plugin:** `claude plugin install miro@melodic-software`. It installs **disabled**
   (`defaultEnabled: false` by design).
3. **Enable it and supply a token:** `claude plugin enable miro` (or the `/plugin` interface). Claude
   Code prompts for the Miro API token at enable time (masked input) and stores it in the system
   keychain — never in `settings.json`. Get a token from
   https://miro.com/app/settings/user-profile/apps with `boards:read` + `boards:write` scopes.
4. **Verify:** in a session with the plugin enabled, `mcp__plugin_miro_miro__*` tools are callable —
   test with "List my Miro boards".

---

## EventStorming Color Mapping

### Miro's 16 Sticky Note Colors

| Miro Color Name | Visual | Hex (approx) |
|----------------|--------|-------------|
| `gray` | Gray | #F5F6F8 |
| `light_yellow` | Light Yellow | #FFF9B1 |
| `yellow` | Yellow | #F5D128 |
| `orange` | Orange | #FF9D48 |
| `light_green` | Light Green | #D5F692 |
| `green` | Green | #93D275 |
| `dark_green` | Dark Green | #67C6C0 |
| `cyan` | Cyan | #23BFE7 |
| `light_pink` | Light Pink | #EA94BB |
| `pink` | Pink | #F16C7F |
| `violet` | Violet | #BE88C7 |
| `red` | Red | #FF3838 |
| `light_blue` | Light Blue | #A6CCF5 |
| `blue` | Blue | #2D9BF0 |
| `dark_blue` | Dark Blue | #414BB2 |
| `black` | Black | #1A1A2E |

### EventStorming → Miro Color + Shape Mapping (Complete — All 16 Colors Assigned)

| EventStorming Element | Book Color | Miro Color | Miro Shape | Match | Content Convention |
|----------------------|------------|------------|------------|-------|-------------------|
| **Domain Event** | Orange | `orange` | `square` | Exact | Past tense: `Order Placed` |
| **Command** | Blue | `blue` | `square` | Exact | Imperative: `Place Order` |
| **Policy** | Lilac/Purple | `violet` | `square` | Close | `Whenever X, do Y` |
| **Actor / Person** | Small Yellow | `yellow` | `square` | Partial* | Role name: `Customer` |
| **Read Model** | Large Yellow/Green | `light_green` | `rectangle` | Partial* | Info needed for decision |
| **External System** | Large Pink | `light_pink` | `rectangle` | Close | System name: `Payment Gateway` |
| **Hot Spot** | Magenta | `red` | `square` | Partial | Prefix with `!!!` |
| **Opportunity / Value Created** | Green | `green` | `square` | Exact | Value description |
| **Value Destroyed** | Red (implied) | `pink` | `square` | Close | Loss/cost description |
| **Aggregate** | Pale Yellow | `light_yellow` | `square` | Exact | Responsibility name (Design-Level only) |
| **Ubiquitous Language** | Special | `gray` | `square` | Workaround | `Term: definition` |
| **Pivotal Event Marker** | Colored tape | `dark_blue` | `rectangle` | Workaround | `--- PIVOTAL: Name ---` |
| **Temporal Milestone** | Varies | `dark_green` | `rectangle` | Workaround | `--- 6 MONTHS BEFORE ---` |
| **Arrow Vote** | Small blue + arrow | `light_blue` | `square` | Partial* | `→ Problem being voted on` |
| **Phase Name (Not-an-Event)** | Orange rotated 45° | `cyan` | `square` | Workaround | `[PHASE] Name` |
| **Reserved / Custom** | Pick an unused color | `black` | `square` | N/A | Domain-specific extension |

*\*Partial = color matches but size cannot be controlled via MCP (API supports `geometry.width` but MCP tool doesn't expose it). Shape (`rectangle` vs `square`) is the workaround for size differentiation.*

**Shape strategy:** Use `rectangle` for "large" building blocks (Read Model, External System) and markers (Pivotal Event, Temporal Milestone). Use `square` for everything else. This provides the visual size signal that distinguishes actors (small square) from read models (large rectangle) even though both can't be resized via MCP.

**Limitations:**

- No sticky note rotation — can't rotate 45° for phase names. Use `cyan` color + `[PHASE]` prefix instead
- No size control via MCP — all stickies default to ~199px. REST API supports `geometry.width` but MCP tool doesn't expose it
- No magenta color — `red` is closest for Hot Spots

---

## Board Setup for EventStorming

### Recommended Board Structure

Create a Miro board with this layout:

1. **Main Timeline** — a long horizontal area for the event flow (left to right)
2. **Legend Frame** — a frame in the top-left corner showing the color mapping
3. **Parking Lot Frame** — for hot spots and items to revisit
4. **Personas Frame** — for actor/persona definitions
5. **Bounded Context Labels** — text labels or frames to mark discovered boundaries

### Positioning Strategy (Tested Values)

Miro uses x,y coordinates with (0,0) at canvas center. Sticky notes are ~199px wide by default.

**Horizontal spacing: 400px between items on the main flow.** This gives ~200px of clear space between stickies. 200px is too tight (stickies touch, text overlaps). For Problems/Opportunities zones with longer text, use 300px minimum.

**Vertical spacing: 250px minimum between ALL adjacent rows.** Sticky notes are ~199px tall. Any spacing below 200px creates overlaps. 250px provides a 50px visual buffer.

**CRITICAL — No reactor sub-rows (v12 lesson).** Using 80px offset between "primary" and "reactor" rows created 212 overlapping stickies. Each persona gets ONE y-row. Track hermit/reactor behavioral mode in persona profile files, not on the board.

### Big Picture Y-Coordinate Table (v13+)

| Element | y | Notes |
|---------|---|-------|
| External Systems (light_pink, rectangle) | -800 | Top of board, 400px horizontal spacing |
| Pivotal Events (dark_blue, rectangle) | -600 | Above persona rows |
| People/Actors (yellow, square) | -400 | 300px horizontal spacing |
| Divergence Markers (red) | -200 | Just above event rows |
| Persona 1 events | 0 | Primary event row |
| Persona 2 events | 500 | 500px spacing between personas |
| Persona 3 events | 1000 | |
| Persona 4 events | 1500 | |
| Persona 5 events | 2000 | |
| Persona 6 events | 2500 | |
| Persona 7 events | 3000 | |
| Persona 8 (Beneficiary — MANDATORY) | 3500 | Per agentic-simulation.md |
| Walk-through new events | 4200 | |
| [STUMBLE] markers | 4500 | 300px below walk-through |
| Reverse narrative events | 4800 | |
| Value Created (green) | 5200 | |
| Value Destroyed (pink) | 5500 | 300px between value rows |
| UL Terms (gray) | 5900 | |
| Problems (violet) | 6200 | 300px in Problems zone |
| Opportunities (light_green) | 6500 | |
| Arrow Votes (light_blue) | 6800 | |
| BC Labels (cyan) | 7100 | Bottom of board |

### Process Modeling Y-Coordinate Table

| Row | y | Purpose |
|-----|---|---------|
| External Systems | -600 | System dependencies |
| Read Models | -400 | Information panels |
| Actors | -200 | Who issues commands |
| **Main Flow** | **0** | **Event-Command-Policy spine** |
| Pass 2 corrections | 300 | Speak Out Loud refinements |
| Exception flows | 600 | Full-chain failure paths |
| Secondary alternatives | 900 | Additional paths |
| Hot spots | 1200 | Open questions |
| Unfulfilled expectations | 1500 | Gaps in process |
| Resolution paths | 1800 | How expectations will be addressed |

### Design-Level Y-Coordinate Table

| Row | y | Purpose |
|-----|---|---------|
| BC Contracts (inbound) | -600 | Consumed events from other BCs |
| Read Models | -400 | Information panels |
| Actors | -200 | Who issues commands |
| Commands | -100 | Blue imperative actions |
| **Aggregates** | **0** | Light yellow — blank first, named last |
| Business Rules | 300 | Gray — invariants (stack at y=300, 550, 800) |
| Domain Events | 1100 | Orange — outcomes |
| Alternative outcomes | 1400 | Rejection/failure events |
| What-if challenges | 1700 | Red hot spots |
| BC Contracts (outbound) | 2000 | Published events |

**Main flow (y=0 baseline):**

- Commands, Events, Policies all sit on y=0
- Flow reads left-to-right, incrementing x by 400 per item

**Above the flow (negative y = up):**

- Actors: y=-250 (directly above their command)
- Read Models: y=-450 (above the actor)
- Hot Spots: y=-250 (above the related event)

**Below the flow (positive y = down):**

- Alternative outcomes: y=+250 (below the happy path event)

**Example: one complete flow segment**

```
Read Model:       x=0,    y=-450
Actor:            x=0,    y=-250
Command:          x=0,    y=0
Domain Event:     x=400,  y=0       (happy path)
Event (alt):      x=400,  y=250     (rejection/failure)
Hot Spot:         x=400,  y=-250    (above the event)
Policy:           x=800,  y=0       (reactive — "whenever")
Next Command:     x=1200, y=0       (triggered by policy)
Next Event:       x=1600, y=0
```

**Legend frame positioning and sizing:**

- Place at x=-800, y=-600 (top-left, out of the main flow)
- **Frame size formula:** `width=500, height = (sticky_count * 200) + 200` — each sticky is ~199px tall with ~50px gap, plus 200px padding top/bottom
- Big Picture legend (4-6 types): `500w x 1400h`
- Process Modeling legend (7 types): `500w x 1600h`
- Design-Level legend (8+ types): `500w x 1800h`
- Legend stickies inside: stack vertically with 200px spacing, starting at the frame's top y + 100px offset
- **Visual check required:** After placing legend stickies, verify via screenshot that all stickies are visible within the frame bounds. Frame overflow = stickies hidden behind the white frame background
- **Do NOT use parent_id** for legend stickies — place them at absolute coordinates within the frame's bounding box. The `parent_id` parameter has MCP reliability issues

**Spacing summary:**

| Direction | Spacing | Reason |
|-----------|---------|--------|
| Horizontal (flow items) | 400px | Room for connectors and labels |
| Vertical (rows) | 250px | Clear separation between layers |
| Legend stickies | 200px vertical | Readable stack |

---

## Agentic Integration

When running simulated EventStorming sessions (see `agentic-simulation.md`), agents can place stickies directly on the Miro board.

### Workflow

1. **Create board** — manually or via API
2. **Share board URL** — provide the board ID to the skill
3. **Agents create stickies** — each persona agent places events using the color mapping above
4. **Attribution** — include persona name in the sticky content (e.g., "[DomainExpert] Order Placed")
5. **Hot spots** — agents flag disagreements by creating red stickies with "!!!" prefix
6. **Review** — human reviews the board, moves stickies, identifies bounded contexts

### Bulk Creation Pattern

The `miro` plugin's server supports bulk creation (up to 20 items per batch) via `miro_bulk_create_sticky_notes`. For a simulated Chaotic Exploration phase:

1. Ask each persona agent to generate their events as structured data
2. Batch-create all stickies on the board
3. Position them roughly along the timeline
4. Review and reorganize (manually or via subsequent agent calls)

---

## Limitations

- **No sticky rotation** — can't rotate stickies 45 degrees (Brandolini's "not an event" signal)
- **No arrows** — can't draw connections between stickies (which is actually consistent with Brandolini's advice to avoid arrows)
- **Bulk limit** — max 20 items per bulk operation
- **Rate limits** — Miro API has rate limits; space out bulk operations
- **No real-time collaboration** — MCP operations are request/response, not live collaborative editing
- **Color approximation** — Miro's 16 colors don't perfectly match physical sticky note colors, but are close enough

## Gotchas (learned from simulation testing)

- **Frame positioning uses center point** — `x, y` is the CENTER of the frame, not the top-left corner. A frame at `x=0, width=6000` spans from `x=-3000` to `x=3000`. Calculate center as: `x = (content_min_x + content_max_x) / 2`
- **Frame z-order** — frames created AFTER stickies render ON TOP, hiding them behind the white frame background. **Only use frames that are created BEFORE their content items and never need resizing.** The legend frame (created once, content placed inside) works well. Timeline frames that grow with each round should be SKIPPED entirely — rely on coordinate-based organization instead. If you delete and recreate a frame, it covers all existing stickies
- **Practical recommendation** — use frames ONLY for the legend (static, created once). For the evolving timeline and content areas, skip frames and let the y-coordinate layering organize the board visually. This avoids all z-order issues
- **Deleting frames with children** — if stickies were created with `parent_id` pointing to a frame, deleting the frame deletes all children. Stickies created WITHOUT `parent_id` survive frame deletion but may be hidden under newly created frames
- **Board sharing via API** — use `sharing_access: "view"` parameter on `miro_create_board` to create public boards. The `miro_update_board` tool can also change sharing after creation. The sharing policy must be nested under `policy.sharingPolicy` in the Miro REST API (POST uses `policy` wrapper, PATCH accepts root-level `sharingPolicy`)

---

## Sources

- [Miro MCP Server Overview](https://help.miro.com/hc/en-us/articles/31624028247058)
- [Miro Developer Docs — MCP Intro](https://developers.miro.com/docs/mcp-intro)
- [Miro Developer Docs — Connecting to Claude Code](https://developers.miro.com/docs/connecting-miro-mcp-to-ai-coding-tools)
- [Miro REST API — Sticky Note Style](https://miroapp.github.io/api-clients/python/miro_api/models/sticky_note_style.html)
- [Miro REST API — Create Sticky Note](https://developers.miro.com/reference/create-sticky-note-item)
