# Steps the improvement lenses share

The steps every lens of `/architecture:improve` (deepening, boundaries, conventions) and
`/architecture:improve-layout` takes the same way. A lens cites the section it uses by name and
states only its own consequence. `<plugin-root>` is the plugin root the calling skill's `SKILL.md`
renders.

## Base freshness

Check the branch is current with its base before a long pass: a base that moves under it lands its
conflicts at the hand-off, after the candidates are shaped around the stale tree. Run each as its
own Bash call, never combined:

1. `git symbolic-ref --short refs/remotes/origin/HEAD` names the base (for example `origin/main`).
2. `git fetch origin <base-branch>` refreshes it.
3. `git rev-list --count HEAD..origin/<base-branch>` counts the commits the branch is behind.

A count above zero is reported with the number, and the user chooses whether to bring the branch
current before the pass starts; no lens merges or rebases on its own. A failure at any step (no
remote, no `origin/HEAD`, offline) is an unknown freshness, said in one line, and the pass carries
on.

## Scope and fan-out

Choose the area first, then scan it:

- When the invocation arguments or the conversation already point somewhere (a pain point, a
  subsystem, a single module), that is the scope, and the history step below is skipped.
- With no direction given, scan first the paths that change most often. Read them with one
  read-only call, `git log --name-only --format='%h %an: %s' -<history_commits>`, longer when no
  pattern shows, and leave out every commit whose author name contains an `exclude_authors` entry,
  and a project's other automation accounts the same way when it names them. Both are improve
  settings ([config.md](config.md), "Improve keys"). When no path
  changes noticeably more than the rest, history sets no priority and the scan covers the whole
  area.
- When a spec or plan for upcoming work is given, scan the areas it will change.

The scope chosen here sets each scan subagent's assigned area.

**Size the fan-out from the scope, not from a constant.** Dispatch one scan subagent per area the
scope decomposed into, since the right width depends on the repository being scanned, not on the
method. Name the count and the areas to the user before dispatching: scan cost rises with the
subagent count, and the scan fan-out is the largest cost of a run.

## Recorded decisions

Read the architecture decision records (ADRs) of the area being examined. When the project declares
where its decisions live inside the repository (a path in its `CLAUDE.md` or rules, or a documented
convention), honor that. Otherwise walk the ladder of common homes in
[adr-discovery.md](adr-discovery.md), from the examined directory up to the repository root. ADR
placement varies widely; a single default glob misses most of them.

## Convention home

Resolve `<home>` by running `bash "<plugin-root>/lib/resolve-convention-home.sh"` from the
repository root, as its own Bash call. The exit code decides the home:

| Exit | Meaning | Home | Report |
|---|---|---|---|
| 0 | One pointer resolved and its directory exists; the home is printed on stdout | The printed home | Nothing |
| 1 | No pointer is recorded | `docs/conventions`, the default home | Nothing |
| 4 | The repository declined a home | `docs/conventions`, the default home; never ask for one | Nothing |
| 5 | Not applicable: the root is `$HOME`, an ancestor of it, or not a git work tree | None | Nothing |
| 2 | Usage error or an unusable root | None | The resolver's message |
| 3 | An invalid pointer, each case with its own message | None | The resolver's message, quoted as printed |
| Any other | Not defined by the resolver | None | The exit code |

With no home, read no file under one, and run any settings read without its file layers. A file
under `<home>` that is absent holds nothing. A lens that writes under `<home>` does so only on
exit 0; on any other exit it writes nothing there and says so in its report.

## Memory-tier writes

A lens's durable run artifacts (a candidate list, a findings file, a generated graph) go to the
memory tier, in the lens's own slice. A lens that writes anything else names where it goes.

- **Memory root.** `<memory_dir>` is `.work/` unless the consuming repository's `CLAUDE.md` or
  `.claude/rules` declares another working-docs root.
- **Slice names.** Each lens names its slice directory and file name. `<topic-slug>` is the scan
  focus the user named (a path, a subsystem or a module), in the invocation arguments or the
  conversation, else the current branch name, kebab-case. `<branch-slug>` is the current branch
  lowercased, with `/` and every character outside `[a-z0-9._-]` replaced by `-`.
- **Before the first write.** Announce the path. Verify the memory root holds a `.gitignore`
  containing `*`, and create it with the Write tool, announced, when absent, never with a shell
  redirect; never edit the repository's own `.gitignore`. Create the slice directory when absent.
- **When to write nothing.** When the memory root is the repository root, or the slice name cannot
  be formed (no branch resolves where the name needs one), write no file: put its content in the
  report instead.
- **Never overwrite.** An existing name takes `-2`, then `-3`.
- **A refused write is not a stop.** When the session's permissions refuse the write, put the
  content in the report and say the file was not written.

Tell the user the path of every file written.

## Badge bands

Order and band the cards by badge, at every count. Cards render in one band per badge, `Strong`
first, then `Worth exploring`, then `Speculative`, and an empty band is left out. The banding is
unconditional: no cap, no pagination, and no card behind a collapsed disclosure, since a reader who
ran the scan needs every candidate and the bands already say how far each claim can be trusted.

## Hand-off

Before handing off, re-run the base-freshness check above and report the behind count, so a base
that moved during the interview surfaces now rather than at merge time.

The hand-off carries two instructions for whoever implements it:

- **A skipped suite is not a pass, and a stub is not the tool.** A test suite that skips because a
  required tool is missing has verified nothing, and a stand-in binary that echoes its arguments and
  exits zero is not the tool it replaces. Validation is green only when the suite ran against the
  real tool.
- **Retiring a public name sweeps comments and assertions, not only call sites.** When the agreed
  change retires a function, type, or other public name, the sweep covers every call site, every
  comment that names it, and every test assertion that mentions it, including a substring assertion
  that would pass against either spelling. A passage that records what a past version dropped (a
  changelog entry, a README history note) keeps the old name, since renaming it would falsify the
  record.

**When more than one candidate is handed off together**, the hand-off also records what a single
candidate never needs: the order the candidates land in and why, the files two or more of them
touch, and which candidates depend on another landing first. Commit granularity and pull-request
shape stay the implementing lane's call and are carried into the hand-off, not decided here.
