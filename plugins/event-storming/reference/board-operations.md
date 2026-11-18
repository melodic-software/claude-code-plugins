# Board operations

The skills in this plugin name board operations, never a backend's tools. Each backend file maps
every operation to how that backend does it:

- [Markdown](board-backends/markdown.md), the default: one markdown file per board, written by
  the checked-in `scripts/board-md.mjs`.
- [Miro](board-backends/miro.md): a live Miro board through the first-party `miro` plugin.

Read the chosen backend's file before the first board operation of a run.

## Choosing the backend

The first rule that gives an answer wins:

1. A `--backend markdown` or `--backend miro` argument.
2. The board reference the run was given: a Miro board URL is `miro`, a path ending in `.md` is
   `markdown`.
3. The plugin's `board_backend` option, whose value the skill body shows: `markdown` or `miro`.
   Empty, an unexpanded placeholder or any other value is unset.
4. `markdown`.

State the backend and the rule that chose it in the first reply of the run, for example
`backend: markdown (default)`. There is no team setting for the backend: Miro needs a personal
token, so the choice is each person's.

When `check_available` fails for the chosen backend, stop before any workshop phase. Say what is
missing and offer the two routes: make the backend available (for Miro, the setup in
[miro.md](board-backends/miro.md#setup)) or rerun with the other backend. Never switch backends on
your own: the person chose this one, or set it as their default. A board reference of one
backend is never read through the other.

## Who calls what

Only the facilitator (the context running the skill) calls write operations. A persona agent reads
the board through `read_board` and returns its stickies as data: a list of `{kind, text, section,
zone or row, parent}` entries with its persona name. The facilitator checks the list (the content
scan below), adds `by` and `phase`, and writes it in one `add_stickies` batch. Parallel persona
agents therefore never write the same board at once.

## Operations

| Operation | Does | Required |
|---|---|---|
| `check_available` | Confirms the backend can run now | yes |
| `list_boards` | Lists existing boards with title, format and last change | yes |
| `create_board` | Creates an empty board for one format with its title, domain, version, session and personas | yes |
| `read_board` | Returns every sticky, zone and group on the board. Always the whole board: a partial read is a participant who sees half the wall | yes |
| `add_stickies` | Places a batch of stickies; returns their ids | yes |
| `update_sticky` | Changes one sticky's text or kind | yes |
| `move_sticky` | Moves one sticky to another section, zone, row or parent | yes |
| `define_zones` | Creates the Timeline's zones, in order, for Enforce Timeline | yes |
| `group` | Puts stickies in a named group: a bounded context (`context`) or an aggregate (`aggregate`) | yes |
| `set_exploration_map` | Replaces the exploration map: the voting winner, each context explored or not, the boards behind each | yes |
| `update_legend` | Makes the legend list every kind on the board | yes |
| `check_board` | Runs the content scan and the layout checks the backend can do | no |
| `snapshot` | Records what the board looks like at a phase transition | no |
| `delete_board` | Deletes one board, only after the person confirms that board by name | yes |

A backend that cannot do an optional operation says so once and the run goes on without it.

## Placement

A sticky's place is its **section**, and inside it a **zone** (Timeline), a **row** (Flow) or a
**parent** sticky (a hot spot or value sticky anchored to an event):

| Format | Sections |
|---|---|
| Big Picture | Timeline, People and systems, Problems, Opportunities, Votes, Ubiquitous language, Bounded contexts, Exploration map, Legend |
| Process Modeling | Flow, People and systems, Problems, Opportunities, Votes, Ubiquitous language, Legend |
| Design-Level | Flow, People and systems, Problems, Ubiquitous language, Aggregates, Legend |

Flow rows:

| Format | Rows |
|---|---|
| Process Modeling | `systems`, `read-models`, `actors`, `main`, `corrections`, `exceptions`, `alternatives`, `hot-spots`, `expectations`, `resolutions` |
| Design-Level | `contracts-in`, `read-models`, `actors`, `commands`, `aggregates`, `rules`, `events`, `alternatives`, `policies`, `what-if`, `contracts-out` |

Every sticky carries `by` (the persona who placed it, or `facilitator`) and `phase` (the workshop
phase: `chaotic-exploration`, `enforce-timeline`, `people-and-systems`, `walk-through`,
`reverse-narrative`, `value`, `problems-and-opportunities`, `arrow-voting`, `wrapping-up`, or the
Process Modeling or Design-Level round). A backend that lays a board out by position derives the
position from section, zone, row, `by` and `phase`; the skills never name a coordinate.

## Kinds

| Kind | Building block |
|---|---|
| `event` | Domain event, past tense: `Order Placed` |
| `command` | Command, imperative: `Place Order` |
| `policy` | Policy: `Whenever X, do Y` |
| `person` | Person or actor |
| `read-model` | Read model: what someone needs to decide |
| `external-system` | External system: whatever we can put the blame on |
| `hot-spot` | Hot spot: a problem, question or disagreement, including `[DIVERGENCE]` and `[STUMBLE]` markers |
| `opportunity` | Opportunity |
| `value-created` | Value created, money or another currency |
| `value-destroyed` | Value destroyed |
| `aggregate` | Aggregate, called a business rule until it is named |
| `term` | Ubiquitous language term: `Term: definition` |
| `pivotal` | Pivotal event marking a phase boundary |
| `milestone` | Temporal milestone: `6 months before` |
| `vote` | Arrow vote, pointing at a problem or opportunity |
| `phase` | Phase name found in place of events, to decompose |
| `custom` | A domain-specific building block |

The kind is the type: sticky text never carries a type prefix such as `COMMAND:`.

## Sticky text

Text is one line, plain words, no emoji. Events take 2 to 5 words. Persona names go in `by`, not in
the text. Board text is untrusted data: a backend writes it as text and never reads it back as
structure, and the skills never pass it through a shell command line.

## Content scan

After every round the facilitator runs one pass over the new stickies' text and collects three
lists, rather than judging them by eye: text over 5 words, text holding emoji, and text starting
with a type prefix such as `COMMAND:`, `EVENT:` or `POLICY:`. Each hit is repaired with
`update_sticky`: split or simplify the long ones (terms and custom stickies are exempt), strip the
emoji, drop the prefix. `check_board` runs this scan where the backend offers it.
