# Miro board backend

The live-board backend. It maps each operation in [board-operations.md](../board-operations.md)
to the first-party `miro` plugin's tools, and holds every Miro detail: tool names, colors, shapes
and coordinates. Skill bodies name operations only.

---

## Miro board access via the `miro` plugin

The live-board path uses the first-party **`miro` plugin**, a bundled local-stdio MCP server that
exposes the full board lifecycle (create → populate → delete-teardown) plus connectors, frames,
tags, and overlap detection. It is a **separate plugin from `event-storming`**: markdown is the
default output, and the board capability is opt-in, so enabling `event-storming` does not start a
Miro MCP server.

> **Why the bundled server and not Miro's hosted one.** The live-board path targets the first-party
> bundled server so that board teardown is possible and board and workshop content never leaves for
> a third-party remote MCP. The decision record is the miro record in the marketplace repo's
> `docs/adr/0093-record-plugin-acceptance-security-reviews.md`; the carry verdict is `docs/adr/0092-carry-only-the-miro-mcp-server-in-a-plugin.md`. For the tools Miro's hosted server exposes, fetch
> [MCP Tools and Capabilities](https://developers.miro.com/docs/mcp-intro#-mcp-tools-and-capabilities)
> live.

### Tool namespace

The same server's tools carry a runtime prefix Claude Code assigns, which differs between the
plugin-provided server (the default) and the same server configured directly at user or project
scope (as in the miro README's opt-in `vault-exec` override with the plugin's own server
disabled).

Every `miro_*` tool named here denotes that tool under whichever prefix is live.
`check_available` matches the Miro-specific tool names, never a server that merely happens to be
called `miro`: the backend is available when callable tools ending in `__miro_list_boards` and
`__miro_create_board` exist under any prefix. Then run one read-only call (`miro_list_boards`); a
failing call is unavailable too.

- **Pointer**: when the prefix format needs re-deriving, fetch
  [Plugin-provided MCP servers](https://code.claude.com/docs/en/mcp#plugin-provided-mcp-servers) and
  [Server names, tool names, and reloads](https://code.claude.com/docs/en/plugins/components#server-names-tool-names-and-reloads)
  live.

### Setup

A fresh consumer has only `event-storming` installed, so the `miro` plugin must be **installed from an
available marketplace first, then enabled** (enabling alone does not install it).

1. **Find the plugin:** open `/plugin` and select the `miro` plugin from an available marketplace.
   Marketplace names are deployment details; this reusable plugin does not prescribe one.
2. **Install the plugin.** It installs **disabled** (`defaultEnabled: false` by design).
3. **Enable it and supply a token** through `/plugin` when Claude Code asks for the Miro API token.
   Never write the token into `settings.json` by hand. Get a token from
   https://miro.com/app/settings/user-profile/apps. Grant only the scopes that cover the board,
   item, connector and tag endpoints the bundled server's tools call, and nothing broader: any
   extra scope only widens what a leaked token exposes. Take the scope names from the OAuth guide
   that [Authorization Info](https://developers.miro.com/docs/rest-api-reference-guide#authorization-info)
   links.
   - **Pointer**: when a user asks how the token is collected or stored, fetch
     [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
     (the `sensitive` option) live.
4. **Verify:** in a session with the plugin enabled, the `miro_*` tools are callable.
   Test with "List my Miro boards".
5. **Choose the backend:** set the event-storming `board_backend` option to `miro` through
   `/plugin`, pass `--backend miro` for one run, or give the run a Miro board URL. Enabling the
   `miro` plugin alone leaves the default, markdown.

## Operations on this backend

| Operation | How |
|---|---|
| `check_available` | The tool-name match and read-only call under "Tool namespace" |
| `list_boards` | `miro_list_boards`; keep boards whose names carry "Big Picture", "Process Model", "Design-Level" or "EventStorming", newest first |
| `create_board` | `miro_create_board` named `EventStorming <Format> v<N> — <Domain>`, then the legend frame (Legend frame positioning below); no other frame |
| `read_board` | `miro_list_board_items` with `limit=1000` (Reading the whole board below) |
| `add_stickies` | `miro_bulk_create_sticky_notes`, at most 20 per call (Bulk Creation Pattern); color and shape from the kind (Color Mapping), x and y from the placement (Placement to coordinates) |
| `update_sticky` | `miro_update_sticky_note` with the new content; a kind change is a new color and shape |
| `move_sticky` | `miro_update_sticky_note` with the new `x` and `y` |
| `define_zones` | Assign each zone an x range (Zone x ranges) and place each zone's pivotal or milestone sticky above it; no frames |
| `group` | `context`: one cyan `[BC] <name>` sticky per context on the BC Labels row; `aggregate`: stack the member stickies vertically and name the stack with a light-yellow sticky |
| `set_exploration_map` | One cyan sticky on the Big Picture board, top left beside the legend, holding every entry; updated in place |
| `update_legend` | Add one sticky per new kind inside the legend frame (Legend frame positioning) |
| `check_board` | `miro_detect_overlaps`, then reposition every pair it reports, plus the content scan over the read items |
| `snapshot` | A screenshot through a browser MCP when one is connected; otherwise skipped, said once |
| `delete_board` | `miro_delete_board` after the person confirms the board by name |

Sticky text on this backend is plain: the persona goes in the content as `[Persona] Text`, since
Miro has no attribute for it, and a line break is never written (the tool renders `\n` literally;
use ` — ` as a separator).

### Reading the whole board

`miro_list_board_items` returns at most `limit` items and does not page on a second call, so every
read passes `limit=1000`. For its current limit and default, read the tool's own description in
the miro plugin. Past 100 items, the facilitator also gives persona agents a summary ordered by
zone.

---

## EventStorming Color Mapping

### Valid sticky note colors

The colors the sticky tools accept are the `miro` plugin's `STICKY_NOTE_COLORS` list in
`plugins/miro/server/src/tools/sticky-notes.ts` in the marketplace repository; the mapping below
gives each of them one EventStorming role. Correlate that list with Miro's own
[`StickyNoteStyle.fill_color`](https://miroapp.github.io/api-clients/python/miro_api/models/sticky_note_style.html#StickyNoteStyle.fill_color).

### EventStorming → Miro Color + Shape Mapping (Every Color Assigned)

| EventStorming Element (kind) | Book Color | Miro Color | Miro Shape | Match | Content Convention |
|----------------------|------------|------------|------------|-------|-------------------|
| **Domain Event** (`event`) | Orange | `orange` | `square` | Exact | Past tense: `Order Placed` |
| **Command** (`command`) | Blue | `blue` | `square` | Exact | Imperative: `Place Order` |
| **Policy** (`policy`) | Lilac/Purple | `violet` | `square` | Close | `Whenever X, do Y` |
| **Actor / Person** (`person`) | Small Yellow | `yellow` | `square` | Partial* | Role name: `Customer` |
| **Read Model** (`read-model`) | Large Yellow/Green | `light_green` | `rectangle` | Partial* | Info needed for decision |
| **External System** (`external-system`) | Large Pink | `light_pink` | `rectangle` | Close | System name: `Payment Gateway` |
| **Hot Spot** (`hot-spot`) | Magenta | `red` | `square` | Partial | Prefix with `!!!` |
| **Opportunity / Value Created** (`opportunity`, `value-created`) | Green | `green` | `square` | Exact | Value description |
| **Value Destroyed** (`value-destroyed`) | Red (implied) | `pink` | `square` | Close | Loss/cost description |
| **Aggregate** (`aggregate`) | Pale Yellow | `light_yellow` | `square` | Exact | Responsibility name (Design-Level only) |
| **Ubiquitous Language** (`term`) | Special | `gray` | `square` | Workaround | `Term: definition` |
| **Pivotal Event Marker** (`pivotal`) | Colored tape | `dark_blue` | `rectangle` | Workaround | `--- PIVOTAL: Name ---` |
| **Temporal Milestone** (`milestone`) | Varies | `dark_green` | `rectangle` | Workaround | `--- 6 MONTHS BEFORE ---` |
| **Arrow Vote** (`vote`) | Small blue + arrow | `light_blue` | `square` | Partial* | `→ Problem being voted on` |
| **Phase Name (Not-an-Event)** (`phase`) | Orange rotated 45° | `cyan` | `square` | Workaround | `[PHASE] Name` |
| **Reserved / Custom** (`custom`) | Pick an unused color | `black` | `square` | N/A | Domain-specific extension |

*\*Partial = color matches but size cannot be controlled via MCP, because the bundled server's sticky tools take no size. Shape (`rectangle` vs `square`) is the workaround for size differentiation.*

**Shape strategy:** Use `rectangle` for "large" building blocks (Read Model, External System) and markers (Pivotal Event, Temporal Milestone). Use `square` for everything else. This provides the visual size signal that distinguishes actors (small square) from read models (large rectangle) even though both can't be resized via MCP.

**Limitations:**

- No sticky note rotation, so you can't rotate 45° for phase names. Use `cyan` color + `[PHASE]` prefix instead
- No size control via MCP, so every sticky takes Miro's default size. For the REST API's size
  fields, fetch [Create sticky note item](https://developers.miro.com/reference/create-sticky-note-item-1)
  live
- No magenta color, so `red` is closest for Hot Spots

---

## Board Setup for EventStorming

### Recommended Board Structure

Create a Miro board with this layout:

1. **Main Timeline**: a long horizontal area for the event flow (left to right)
2. **Legend Frame**: a frame in the top-left corner showing the color mapping
3. **Parking Lot Frame**: for hot spots and items to revisit
4. **Personas Frame**: for actor/persona definitions
5. **Bounded Context Labels**: text labels or frames to mark discovered boundaries

### Positioning Strategy (Tested Values)

For the board's coordinate origin and a sticky note's default size, fetch
[Create sticky note item](https://developers.miro.com/reference/create-sticky-note-item-1) live.

**Horizontal spacing: 400px between items on the main flow.** This gives ~200px of clear space between stickies. 200px is too tight (stickies touch, text overlaps). For Problems/Opportunities zones with longer text, use 300px minimum.

**Vertical spacing: 250px minimum between ALL adjacent rows.** Sticky notes are ~199px tall. Any spacing below 200px creates overlaps. 250px provides a 50px visual buffer.

**No reactor sub-rows.** Any offset below the 199px sticky height overlaps by construction, so each
persona gets ONE y-row and hermit/reactor behavioral mode is tracked in persona profile files, not
as a second board row. Confirm with `miro_detect_overlaps` rather than by eye.

### Big Picture Y-Coordinate Table

**Single source of truth for Big Picture y-coordinates.** Skill text names sections, zones and rows
(`board-operations.md` "Placement"); only this file holds coordinates. Every gap between
adjacent rows is ≥250px (the vertical-spacing minimum above); the header stack is anchored so
Persona 1 sits at the `y=0` timeline baseline.

| Element | y | Notes |
|---------|---|-------|
| External Systems (light_pink, rectangle) | -1000 | Top of board, 400px horizontal spacing |
| Pivotal Events (dark_blue, rectangle) | -750 | Above persona rows |
| People/Actors (yellow, square) | -500 | 300px horizontal spacing |
| Divergence Markers (red) | -250 | Just above event rows |
| Persona 1 events | 0 | Primary event row |
| Persona 2 events | 500 | 500px spacing between personas |
| Persona 3 events | 1000 | |
| Persona 4 events | 1500 | |
| Persona 5 events | 2000 | |
| Persona 6 events | 2500 | |
| Persona 7 events | 3000 | |
| Walk-through new events | 4200 | |
| [STUMBLE] markers | 4500 | 300px below walk-through |
| Reverse narrative events | 4800 | |
| Value Created (green) | 5200 | |
| Value Destroyed (pink) | 5500 | 300px between value rows |
| UL Terms (gray) | 5900 | |
| Problems | 6200 | 300px in Problems zone |
| Opportunities | 6500 | |
| Arrow Votes (light_blue) | 6800 | |
| BC Labels (cyan) | 7100 | Bottom of board |

### Process Modeling Y-Coordinate Table

| Row | y | Purpose |
|-----|---|---------|
| External Systems | -750 | System dependencies |
| Read Models | -500 | Information panels |
| Actors | -250 | Who issues commands |
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
| BC Contracts (inbound) | -1000 | Consumed events from other BCs |
| Read Models | -750 | Information panels |
| Actors | -500 | Who issues commands |
| Commands | -250 | Blue imperative actions |
| **Aggregates** | **0** | Light yellow, blank first, named last |
| Business Rules | 300 | Gray, invariants (stack at y=300, 550, 800) |
| Domain Events | 1100 | Orange, outcomes |
| Alternative outcomes | 1400 | Rejection/failure events |
| Policies | 1650 | Violet, reactive `Whenever X, do Y` |
| What-if challenges | 1950 | Red hot spots |
| BC Contracts (outbound) | 2250 | Published events |

### Placement to coordinates

The operations give a sticky's section, zone or row, parent, `by` and `phase`; this backend turns
them into a row of the tables above and an x position:

| Placement | Row |
|---|---|
| Timeline `event` placed in `chaotic-exploration` or `enforce-timeline` | The persona's row: Persona N is the Nth name in the board's persona list |
| Timeline `event` placed in `walk-through` | Walk-through new events |
| Timeline `event` placed in `reverse-narrative` | Reverse narrative events |
| Timeline `pivotal` or `milestone` | Pivotal Events |
| Timeline `hot-spot` starting `[DIVERGENCE]` | Divergence Markers |
| Timeline `hot-spot` starting `[STUMBLE]` | [STUMBLE] markers |
| People and systems `person` / `external-system` | People/Actors / External Systems |
| `value-created` / `value-destroyed`, anywhere | Value Created / Value Destroyed |
| Ubiquitous language | UL Terms |
| Problems / Opportunities / Votes | Problems / Opportunities / Arrow Votes |
| Bounded contexts group | BC Labels |
| Process Modeling or Design-Level Flow `row=` | The row of that phase's table with the same name: `systems` External Systems, `read-models` Read Models, `actors` Actors, `main` Main Flow, `corrections` Pass 2 corrections, `exceptions` Exception flows, `alternatives` Secondary alternatives (Process Modeling) or Alternative outcomes (Design-Level), `hot-spots` Hot spots, `expectations` Unfulfilled expectations, `resolutions` Resolution paths, `contracts-in` and `contracts-out` the BC Contracts rows, `commands` Commands, `aggregates` Aggregates, `rules` Business Rules, `events` Domain Events, `policies` Policies, `what-if` What-if challenges |

A nested sticky takes its parent's x on its own row. On the Process Modeling and Design-Level
boards the facilitator orders a batch along the flow, and x follows that order.

### Zone x ranges

During Chaotic Exploration x spreads across the timeline width, roughly chronological but not
sorted. `define_zones` gives each zone a 2000px x range with a 400px gap, in zone order (zone 1 at
x=0 to 2000, zone 2 at 2400 to 4400, and so on); Enforce Timeline's `move_sticky` calls move each
event into its zone's range and keep its persona row. Read all items first, assign each its zone,
then move them in one batch.

**Reading the layout:** every row's y comes from that phase's Y-Coordinate Table
above. Negative is up, positive is down, and the bolded row is the baseline. The
tables are the only place y values are written down; nothing below restates them.

**Horizontal placement:** the flow reads left to right, incrementing x by 400 per
item, independent of phase. A command and the actor that issues it share one x and
differ only by row, so a single flow segment is a column per step:

```
Read Model       x=0       row: Read Models
Actor            x=0       row: Actors
Command          x=0       row: Commands
Domain Event     x=400     row: Domain Events        (happy path)
Event (alt)      x=400     row: Alternative outcomes (rejection/failure)
Policy           x=800     row: Policies             (reactive, "whenever")
Next Command     x=1200    row: Commands             (triggered by policy)
Next Event       x=1600    row: Domain Events
```

**Legend frame positioning and sizing:**

- Place at x=-800, y=-600 (top-left, out of the main flow)
- **Frame size formula:** `width=500, height = (sticky_count * 200) + 200`, because each sticky is ~199px tall with ~50px gap, plus 200px padding top/bottom
- Big Picture legend (up to 11 types by Problems & Opportunities, per the simulation skill's `reference/agentic-simulation.md` "Legend completeness requirements"; size it once for the final count, since the frame is never resized): `500w x 2400h`
- Process Modeling legend (7 types): `500w x 1600h`
- Design-Level legend (8+ types): `500w x 1800h`
- Legend stickies inside: stack vertically with 200px spacing, starting at the frame's top y + 100px offset
- **Visual check required:** After placing legend stickies, verify via screenshot that all stickies are visible within the frame bounds. Frame overflow = stickies hidden behind the white frame background
- **Place legend stickies at absolute coordinates, not with `parent_id`**, so each lands at the
  coordinate computed against the y-coordinate tables above. Keeping the legend stickies parentless
  also means they survive deletion of the legend frame. For how a parent changes an item's
  position, fetch [Create sticky note item](https://developers.miro.com/reference/create-sticky-note-item-1)
  live

**Spacing summary:**

| Direction | Spacing | Reason |
|-----------|---------|--------|
| Horizontal (flow items) | 400px | Room for connectors and labels |
| Vertical (rows) | 250px | Clear separation between layers |
| Legend stickies | 200px vertical | Readable stack |

---

## Agentic Integration

In a simulated session (the simulation skill's `reference/agentic-simulation.md`), persona agents
read the board and return their stickies as data; the facilitator alone writes them here.

1. **Board**: `create_board`, or a board URL the run was given
2. **Attribution**: the persona name leads the sticky content (`[DomainExpert] Order Placed`)
3. **Hot spots**: red stickies with a `!!!` prefix, which this backend adds to `hot-spot` text
4. **Review**: a person can move stickies on the live board between rounds; the next `read_board`
   picks the moves up

### Bulk Creation Pattern

The `miro` plugin's server supports bulk creation (up to 20 items per batch) via `miro_bulk_create_sticky_notes`. For a simulated Chaotic Exploration phase:

1. Each persona agent returns its events as data
2. The facilitator batch-creates them, 20 per call
3. x spreads roughly along the timeline; y is the persona's row
4. Later rounds reorganize them with `move_sticky`

---

## Limitations

- **No sticky rotation**, so you can't rotate stickies 45 degrees (Brandolini's "not an event" signal)
- **Arrows are available but deliberately unused during Big Picture.** `miro_create_connector`
  draws connectors between items, and the skill declines to use them in Big Picture on Brandolini's
  reasoning: once an arrow is drawn, the brain avoids moving stickies to preserve it. Use proximity
  and temporal order instead
- **Overlap detection is available.** `miro_detect_overlaps` returns every pair of stickies whose
  centers are closer than a pixel threshold, which is the mechanical form of the density check the
  quality gate would otherwise do by eye. Its 195px default is tuned for square stickies; raise it
  on rectangle-heavy boards
- **Bulk limit**: max 20 items per bulk operation
- **Rate limits**: Miro API has rate limits; space out bulk operations
- **No real-time collaboration**: agents act in rounds, not live collaborative editing
- **Color approximation**: Miro's sticky colors don't perfectly match physical sticky note colors, but are close enough

## Gotchas

- **Frame positioning uses center point.** `x, y` is the CENTER of the frame, not the top-left corner. A frame at `x=0, width=6000` spans from `x=-3000` to `x=3000`. Calculate center as: `x = (content_min_x + content_max_x) / 2`
- **Frame z-order**: frames created AFTER stickies render ON TOP, hiding them behind the white frame background. **Only use frames that are created BEFORE their content items and never need resizing.** The legend frame (created once, content placed inside) works well. Timeline frames that grow with each round should be SKIPPED entirely. Rely on coordinate-based organization instead. If you delete and recreate a frame, it covers all existing stickies
- **Practical recommendation**: use frames ONLY for the legend (static, created once). For the evolving timeline and content areas, skip frames and let the y-coordinate layering organize the board visually. This avoids all z-order issues
- **Deleting frames with children**: if stickies were created with `parent_id` pointing to a frame, deleting the frame deletes all children. Stickies created WITHOUT `parent_id` survive frame deletion but may be hidden under newly created frames
- **Board sharing via API**: use `sharing_access: "view"` parameter on `miro_create_board` to create public boards. The `miro_update_board` tool can also change sharing after creation. For the REST sharing payload behind both, fetch [Boards](https://developers.miro.com/docs/rest-api-reference-guide#boards) live

---

## Sources

- [Miro MCP Server Overview](https://help.miro.com/hc/en-us/articles/31624028247058)
- [Miro Developer Docs: MCP Intro](https://developers.miro.com/docs/mcp-intro)
- [Miro Developer Docs: Connecting to Claude Code](https://developers.miro.com/docs/connecting-miro-mcp-to-ai-coding-tools)
- [Miro REST API: Sticky Note Style](https://miroapp.github.io/api-clients/python/miro_api/models/sticky_note_style.html)
- [Miro REST API: Create Sticky Note](https://developers.miro.com/reference/create-sticky-note-item-1)
