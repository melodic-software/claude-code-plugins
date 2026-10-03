# Status report page

Genre: reports and status. The printed brief is the record; the page is a view of it, written
outside any record and never read back.

## When

Only in an interactive session that can serve a file. A scheduled run, CI, or any run with no one
reading prints the brief and stops.

## Content class

The brief carries issue and pull-request titles and RECOMMENDED lines, so the page is K2: built by
`scripts/build-brief-view.mjs` from `templates/brief.html` and the brief's lines as escaped JSON
data, never from markup or script you write. Do not edit the page after it is built.

## Resolve the medium

Before running the script, first hit wins:

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
| `terminal` | The brief only. Build nothing. |
| `file`, or `auto` in an interactive session | Build the page to an untracked temp file and tell the reader its path. |
| `artifact` | Build the page, then publish that file with the Artifact tool when it is available. Otherwise take the `file` row and say why. Publishing does not lower the page's class. |

Any other value is reported and treated as `auto`. Name the layer that supplied the value when you
report the choice. Pointer: `docs/conventions/rendered-views/README.md` in the marketplace repository,
"The `rendered-views` cascade concern".

## Build

When the medium calls for a page, run the script once into a file, print that file, then build from it,
so the page is built from the same bytes the reader sees and the queries run once:

```bash
bash "<plugin-root>/skills/morning-brief/scripts/morning-brief.sh" $ARGUMENTS > "<dir>/morning-brief.txt"
```

When that exits non-zero (4 or 5 included), print the script's message, build nothing, and stop. Otherwise
print the file, then run:

```bash
node "<plugin-root>/skills/morning-brief/scripts/build-brief-view.mjs" --out "<dir>/morning-brief.html" < "<dir>/morning-brief.txt"
```

`<dir>` is a temp directory. The page follows the printed brief. Each `== Section ==`
becomes a collapsible block, all open, and one filter box matches any word on any line: a PR or
issue number, a lane, a flag, a word of a title.

A non-zero exit from the builder means the page failed its profile: report the message and keep the
brief. Do not hand-write the page as a fallback. Exit 2 with node missing: say the page was not built.
