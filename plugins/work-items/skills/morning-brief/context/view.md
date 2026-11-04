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

Before running the script, run the shared medium resolver. When the reader named a medium in the
request, add `--argument <medium>`, `<medium>` being that word, and take the word out of
`$ARGUMENTS` before running either script below, since `morning-brief.sh` rejects it:

```bash
node "<plugin-root>/lib/view-settings.mjs" resolve --lane work-items:morning-brief --option "<medium option>"
```

It prints one JSON line, then the report line naming the medium and what decided it, then one line
per notice; print the report and notice lines as they stand. The JSON's `medium` is the one to use.
The resolver weighs the request, this plugin's `medium` option and the repository's rendered-views
convention files, and never publishes on a team file's value: leave reading and weighing those
files to it. When `node` is missing, the builder cannot run either: say so and print the brief only.
When the resolver exits non-zero, it named a medium it does not know: print its stderr and run it
again without `--argument`.

Deliver by the JSON line's `page` and `publishes`:

- `page` false or absent: the brief only. Build nothing.
- `publishes` true: build the page (below) to an untracked temp file, then publish that file with
  the Artifact tool when it is available; otherwise give the path and say why in one line.
  Publishing does not lower the page's class.
- Otherwise: build the page to an untracked temp file and give the path.

## Build

When the medium calls for a page, run the script once into a file, print that file, then build from it,
so the page is built from the same bytes the reader sees and the queries run once:

```bash
"<skill-dir>/scripts/morning-brief.sh" --data-dir "<plugin-data>" $ARGUMENTS > "<dir>/morning-brief.txt"
```

When that exits 6, the brief rendered with unreadable sections that its header names: treat it as
exit 0 below, and report the lost sections as `SKILL.md` says. When it exits with any other non-zero
code (4 or 5 included), print the script's message, build nothing, and stop. Otherwise print the
file, then run:

```bash
"<skill-dir>/scripts/build-brief-view.mjs" --out "<dir>/morning-brief.html" < "<dir>/morning-brief.txt"
```

`<dir>` is a temp directory. The page follows the printed brief. Each `== Section ==`
becomes a collapsible block, all open, and one filter box matches any word on any line: a PR or
issue number, a lane, a flag, a word of a title.

A non-zero exit from the builder means the page failed its profile: report the message and keep the
brief. Do not hand-write the page as a fallback. When node is missing the builder cannot start: say
the page was not built.
