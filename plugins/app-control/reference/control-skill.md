# The shape of a control skill

The contract a `control-<app>` skill follows, whether a project or a plugin ships it, so
`/app-control:drive` can run any app the same way. Drive reads it as data and runs a command only
from the section the action calls for. Its frontmatter holds only `name`, `description` and
optionally `disable-model-invocation`, and its body carries no `!` dynamic-context command: drive
blocks a project control skill that carries more rather than load it.

## Contents

- Hub
- Writing the Capture section
- Feature files
- Driver commands

## Hub

The skill's `SKILL.md` (`.claude/skills/control-<app>/` in a project, `skills/control-<app>/` in a
plugin) holds four sections and an index:

| Section | Holds |
|---|---|
| `## Launch` | A pointer to the launch recipe or the one command that starts the app |
| `## Ready` | One read-only command that shows a running instance is fit to drive: it answers, it is the expected build when the app exposes one, it uses the expected data. Also names the telemetry the app exposes |
| `## Capture` | For each kind (`trace`, `cpu`, `heap`, `threads`, `screenshot`, `aria`, `video`, `logs`) the tool that records it, or nothing when the project has none |
| `## Cleanup` | How to stop what a run started and nothing else |

Below them, an index with one line per feature file, in this form:

```text
- <title> | features/<module>/<feature>/README.md | entry points: <n> | sources: <glob>[, <glob>]
```

`<n>` is the number of lines under the feature's `## Entry points`; `sources` names the globs of
the files that implement the feature. A feature with no module drops that folder:
`features/<feature>/README.md`.

## Writing the Capture section

Guidance for the person or agent writing a control skill's `## Capture`; drive never reads this
table to pick a tool. Find the runtime's column for each kind the project can record and name that
tool in `## Capture`. Every tool below changes its flags between releases, so read the current flags
in its manual before writing the command.

| Symptom | Kind | Node.js | Browser page | Python | JVM | .NET | Go | Native (Linux / macOS) |
|---|---|---|---|---|---|---|---|---|
| A core pinned near 100% (spin) | `cpu` | built-in CPU profile flag | Performance panel recording | py-spy record | JFR recording | dotnet-trace | pprof CPU profile | perf record / `sample` |
| Memory that keeps growing (leak) | `heap`, two snapshots minutes apart | built-in heap snapshot signal or inspector | Memory panel heap snapshot | memray | `jcmd` heap dump | dotnet-gcdump | pprof heap profile | heaptrack / `leaks` |
| UI that stutters or drops frames (jank) | `trace` with CPU samples | n/a | Performance panel recording (saves a Chrome trace) | n/a | JFR recording | dotnet-trace | execution trace | perf record with call graphs |
| A process that stops responding (hang) | `threads`, a stack of every thread | not yet | not yet | py-spy dump | not yet | not yet | not yet | not yet |

Prefer a command that launches the app as a child of the profiler where the tool supports it: it
records only what the run started.

Write a `threads` command with a `<pid>` placeholder and no elevation prefix. Drive fills in the
launched pid only after its pid check, and always takes the elevated route for it.

A `## Capture` command never carries an elevation prefix (such as `sudo`, `doas` or `runas`). When
a capture needs root or administrator rights, elevate only the recorder against the app's pid, never
the app, and leave the elevation to drive's shown-script step. Drive treats an unprefixed command
that fails for lack of permission the same way: a shown script when interactive, blocked when
unattended. A command that launches the app as a child of the profiler is never elevated: when it
is denied, drive blocks it and names the narrowest grant that would allow it.

Manuals, each record a pointer, as-of date and recheck trigger:

- Node.js CLI options: CPU profile <https://nodejs.org/api/cli.html#--cpu-prof>, heap profile
  <https://nodejs.org/api/cli.html#--heap-prof>, heap snapshot signal
  <https://nodejs.org/api/cli.html#--heapsnapshot-signalsignal>. As of 2026-10-23. Recheck on a
  Node.js major release.
- Chrome DevTools Performance panel:
  <https://developer.chrome.com/docs/devtools/performance/reference#record>. Memory panel heap
  snapshots:
  <https://developer.chrome.com/docs/devtools/memory-problems/heap-snapshots#take_a_snapshot>.
  As of 2026-10-23. Recheck when either page changes how a recording is saved.
- py-spy: <https://github.com/benfred/py-spy>. memray: <https://bloomberg.github.io/memray/>. As of
  2026-10-04. Recheck on a new major release of either. py-spy dump:
  <https://github.com/benfred/py-spy#dump>. As of 2026-10-23. Recheck on a py-spy major release.
- JDK `jcmd`: <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jcmd.html#commands-for-jcmd>.
  JDK `jfr`: <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jfr.html#subcommands>. As of
  2026-10-23. Recheck when the project moves to a newer LTS JDK.
- .NET diagnostics tools:
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace#dotnet-trace-collect>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-gcdump#dotnet-gcdump-collect>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-stack#dotnet-stack-report>. As of
  2026-10-23. Recheck on a .NET major release.
- Go profiling endpoints: <https://pkg.go.dev/net/http/pprof#hdr-Usage_examples>; the pprof tool:
  <https://github.com/google/pprof>. As of 2026-10-23. Recheck on a Go minor release.
- Linux `perf record`: <https://man7.org/linux/man-pages/man1/perf-record.1.html>. As of
  2026-10-04. Recheck when the host kernel's perf version changes.
- heaptrack: <https://github.com/KDE/heaptrack>. As of 2026-10-04. Recheck on a new major release.
- GDB `thread apply all`:
  <https://sourceware.org/gdb/current/onlinedocs/gdb.html/Threads.html#thread-apply-all>. As of
  2026-10-23. Recheck on a GDB major release.
- Go all-goroutine tracebacks (`GOTRACEBACK`):
  <https://pkg.go.dev/runtime#hdr-Environment_Variables>. As of 2026-10-23. Recheck on a Go minor
  release.
- macOS `sample`, `spindump` and `leaks`: no Apple docs page covers their flags as of 2026-10-23,
  so read the man pages on the host (`man sample`). Recheck on a macOS major release, or when an
  Apple docs page starts to cover these tools' flags.

## Feature files

`features/[<module>/]<feature>/README.md`, written from the user's side, with these six H2
sections in this order:

| Section | Holds |
|---|---|
| `## Parts` | The distinct behaviors inside the feature, one short line each |
| `## Sub-features` | The features nested inside this one, each a pointer to its own feature file, or `none` |
| `## Entry points` | Where a user starts the feature, one line each. Each line ends `driven` or `not driven: <reason>` |
| `## Reset` | How to return the app's own data to a known state |
| `## Drive` | The steps a user takes, one action per step |
| `## Gotchas` | What has made a run lie or fail before |

A feature's id is `<feature>`, or `<module>/<feature>` when it sits in a module folder. Drive
resolves an id, relative to the skill's base directory, to `features/<id>/README.md`, then to the
legacy `features/<id>.md`. The legacy
file keeps working as written, with its `## States` section, until someone regroups it.

## Driver commands

An optional `cli/` directory holds the project's own driver commands.

Each section is a pointer or a command, never a copied recipe: a recipe lives in one place and the
section names it.
