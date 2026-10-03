# Triage board page

Genre: reports and status. The attention view's table is the record; the page is a view of it,
written outside any record and never read back.

## When

Only in an interactive session that can serve a file, and only for the attention view (no number).
A loop lane, CI, or any run with no one reading prints the table and stops.

## Content class

Item titles, labels and blocker numbers are tracker text, so the page is K2: built by
`scripts/build-board.mjs` from `templates/board.html` and the items as escaped JSON data, never from
markup or script you write. Do not edit the page after it is built, and do not paste an item body
into it: the board holds titles, labels, state and blockers only.

## Resolve the medium

First hit wins:

1. The `medium` key of the `rendered-views` cascade: read whichever of `~/.claude/rendered-views.md`,
   `<root>/.claude/rendered-views.md` and `<root>/.claude/rendered-views.local.md` exist. `<root>` is
   `${CLAUDE_PROJECT_DIR}` when set, otherwise `git rev-parse --show-toplevel`, never the working
   directory. When `<root>` is `$HOME`, an ancestor of `$HOME`, or not inside a git working tree, the team
   and overlay layers are not applicable: say so and read the user-global layer only. A team or overlay path
   that is the same file as the user-global one is skipped. A team layer that is not tracked is a hard stop;
   an overlay that is staged or not gitignored is reported, not honored. The last layer that states
   `medium:` wins. A layer that is malformed is reported and treated as absent.
2. `auto`, which is also the value when no layer states one.

| `medium` | Result |
|---|---|
| `terminal` | The table only. Build nothing. |
| `file`, or `auto` in an interactive session | Build the page to an untracked temp file and tell the reader its path. |
| `artifact` | Build the page, then publish that file with the Artifact tool when it is available. Otherwise take the `file` row and say why. Publishing does not lower the page's class. |

Any other value is reported and treated as `auto`. Name the layer that supplied the value when you
report the choice. Pointer: `docs/conventions/rendered-views/README.md` in the marketplace repository,
"The `rendered-views` cascade concern".

## Build

After the table, write the items the table lists to a JSON file in a temp directory with the Write
tool, not through a shell heredoc, then run:

```bash
node "<plugin-root>/skills/triage/scripts/build-board.mjs" --out "<dir>/triage-board.html" < "<dir>/items.json"
```

```json
{"repo":"owner/name","generated":"2026-10-03","items":[
  {"number":1,"title":"","kind":"issue","state":"unlabeled","labels":[""],"blockedBy":[2]}]}
```

- `state` is the attention-view bucket the item came from: `unlabeled`, `raw marker`, or `needs-info reply`.
- `kind` is `issue` or `PR`.
- Give `blockedBy` (the issue numbers on the item's native blocked-by edges) only when the listing
  read them. Leave it out otherwise: the board then groups the item under "blockers not read" instead
  of calling it unblocked.

The board groups the same items three ways, each section collapsible: by state, by blocker, and by
label (an item appears under each of its labels). Each section has one filter box that matches any
word of a row: a label, state, blocker, number or title word. Items keep the table's oldest-first
order inside a group, and groups run largest first.

A non-zero exit means the input or the page failed its profile: report the message and keep the
table. Do not hand-write the page as a fallback. Exit 2 with node missing: say the page was not built.
