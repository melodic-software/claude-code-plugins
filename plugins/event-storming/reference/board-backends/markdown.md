# Markdown board backend

The default backend. A board is one markdown file a person can read, diff and edit by hand. This
file defines the format and maps each operation in [board-operations.md](../board-operations.md)
to how the markdown backend does it.

## Where boards live

Each session writes its boards under the board directory, one folder per session:

```text
<board_dir>/<session-id>/big-picture.md
<board_dir>/<session-id>/process-modeling-<bc-slug>.md
<board_dir>/<session-id>/design-level-<bc-slug>.md
```

`<board_dir>` is the team file's `board_dir` key (`event-storming.yaml` in the convention home),
default `docs/event-storming`, relative to the repository root. The skill writes these files and
never stages or commits them: whether a board is committed is the person's call. Outside a git
repository, or at a root that is the home directory or one of its ancestors, the skill asks for a
directory instead of writing one. `<bc-slug>` is the bounded context's name, lower-case, with
every run of other characters turned into one `-`.

## Who writes

Every write goes through the checked-in script `${CLAUDE_PLUGIN_ROOT}/scripts/board-md.mjs`;
people edit the file by hand with any editor. The facilitator is the only caller of write
operations. Persona agents read the board with the Read tool and return their stickies as data
(kind, text, section, zone or row), and the facilitator applies them in one batch.

| Command | Does |
|---|---|
| `board-md.mjs new <board.md> <meta.json>` | Creates the file with its frontmatter and every section; refuses an existing path |
| `board-md.mjs apply <board.md> <ops.json>` | Applies a list of operations, all or none, and prints the ids it assigned |
| `board-md.mjs check <board.md>` | Prints `error:` and `warn:` lines; exit 1 on any error |
| `board-md.mjs parse <board.md>` | Prints the board as JSON |

Write the `meta.json` and `ops.json` inputs with the Write tool to a scratch path outside the
board directory (the session directory), never as a shell heredoc or argument: board text is
untrusted and never appears in a command line. `apply` refuses a board that fails `check`, and
refuses any batch whose result would fail it; the file is left unchanged either way.

## File format

### Frontmatter

```yaml
---
board: event-storming/1
format: big-picture
title: Big Picture v1 - Online Course Marketplace
domain: Online Course Marketplace
version: 1
session: courses-20261118-a7f2
phase: walk-through
updated: "2026-11-18T05:30:00Z"
personas:
  - Instructor
  - Support Agent
---
```

`board`, `format` (`big-picture`, `process-modeling` or `design-level`) and `title` are required.
A value that is not plain letters, digits, spaces and `._/-` is written double-quoted, JSON
escaping inside the quotes.

### Sections

A level-1 title follows the frontmatter, then the format's level-2 sections in this order:

| Format | Sections |
|---|---|
| `big-picture` | Timeline, People and systems, Problems, Opportunities, Votes, Ubiquitous language, Bounded contexts, Exploration map, Legend |
| `process-modeling` | Flow, People and systems, Problems, Opportunities, Votes, Ubiquitous language, Legend |
| `design-level` | Flow, People and systems, Problems, Ubiquitous language, Aggregates, Legend |

- **Timeline** holds level-3 zones (`### Onboarding {#z1}`), added by `define_zones`. Stickies
  placed before any zone exists sit directly under the heading: that is the chaotic exploration.
- **Flow** has no zones; each sticky carries `row=` naming its row (for example `main`,
  `exceptions`, `alternatives`, `actors`, `read-models`, `systems`, `rules`, `contracts-in`,
  `contracts-out`). Rows replace the board-coordinate rows a canvas uses.
- **Bounded contexts** and **Aggregates** hold groups: a level-3 heading with an id, then one
  `- #<id>` line per member sticky. Membership lives only here; a sticky names no group, and a
  sticky sits in at most one group per section.
- **Exploration map** holds `- <label>: <value>` lines, replaced as a whole by
  `set_exploration_map`.
- **Legend** is regenerated on every write: a table of each kind on the board and its meaning.
  Hand edits to it are dropped.
- A section the format does not list is kept verbatim and reported by `check` as a warning.

### Stickies

```markdown
- [event] Course Published {#s12 by=Instructor}
  - [hot-spot] Who approves a course? {#s13 by="Support Agent"}
- [vote] Refund disputes take 6+ days {#s40 by=Finance on=s31}
```

- One line per sticky: `- [<kind>] <text> {#<id> <key>=<value>...}`. Kinds are the vocabulary in
  [board-operations.md](../board-operations.md#kinds). Keys: `by` (the persona), `phase` (the
  workshop phase that placed it), `row` (Flow only), `on` (a vote's target id). A value with
  anything but letters, digits and `._:-` is double-quoted.
- Ids are `s<N>` for stickies, `z<N>` for zones and `g<N>` for groups, each the next number after
  the highest on the board, so the same batch on the same board gives the same ids. A hand-added
  sticky line without the brace block is valid; the next `apply` gives it an id.
- A sticky indented two spaces belongs to the sticky above it (a hot spot or a value sticky
  anchored to an event). Nesting is one level deep, and a moved sticky takes its nested stickies
  with it.
- Text is one line. `apply` turns line breaks and control characters into spaces and escapes
  `` \ ` * _ { } [ ] < > | # `` with a backslash, so text renders as typed and never reads back as
  a heading, an id, an attribute or a link. Never pre-escape text passed to `apply`.

## Operations on this backend

| Operation | How |
|---|---|
| `check_available` | `node --version` succeeds and the board directory resolves. No node: say so and render the model in the reply instead of a file |
| `list_boards` | Glob `<board_dir>/*/*.md` and read each file's frontmatter |
| `create_board` | `board-md.mjs new` |
| `read_board` | Read the whole file with the Read tool, or `board-md.mjs parse` for JSON |
| `add_stickies` | `apply` with `{"op":"add","section":"Timeline","zone":"Onboarding","kind":"event","text":"…","by":"…","phase":"…"}` per sticky; `parent` instead of `section` nests it, `row` places it in Flow |
| `update_sticky` | `{"op":"update","id":"s12","text":"…"}`; `kind`, `by`, `phase`, `row` and `on` too, `null` removes a key |
| `move_sticky` | `{"op":"move","id":"s12","section":"Timeline","zone":"Purchase"}`, or `parent`, or `row` |
| `define_zones` | `{"op":"zones","names":["Onboarding","Purchase"]}`; an existing zone is kept |
| `group` | `{"op":"group","section":"Bounded contexts","name":"Payments","members":["s4","s9"]}`; `id` renames or re-members an existing group |
| `set_exploration_map` | `{"op":"exploration-map","entries":[{"label":"Winner","value":"…"}]}` |
| `update_legend` | Nothing to do: every write regenerates it |
| `check_board` | `board-md.mjs check`; its warnings are the content scan |
| `snapshot` | Not needed: the file is the snapshot, and git shows its changes once a person commits it |
| `delete_board` | After the person confirms, delete the file with the host shell; never a directory sweep |

`{"op":"meta","phase":"…","personas":[…]}` updates the frontmatter. Every batch with at least one
operation sets `updated`.
