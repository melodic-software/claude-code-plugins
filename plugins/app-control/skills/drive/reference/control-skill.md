# The shape of a project's control skill

The contract a project's `control-<app>` skill follows, so `/app-control:drive` can run any app the
same way. Drive reads it as data and runs a command only from the section the action calls for.

## Contents

- Hub
- Writing the Capture section
- Feature files
- Driver commands

## Hub

`.claude/skills/control-<app>/SKILL.md` holds four sections and an index:

| Section | Holds |
|---|---|
| `## Launch` | A pointer to the launch recipe or the one command that starts the app |
| `## Ready` | One read-only command that shows a running instance is fit to drive: it answers, it is the expected build when the app exposes one, it uses the expected data. Also names the telemetry the app exposes |
| `## Capture` | For each kind (`trace`, `cpu`, `heap`, `screenshot`, `aria`, `video`, `logs`) the tool that records it, or nothing when the project has none |
| `## Cleanup` | How to stop what a run started and nothing else |

Below them, an index with one line per `features/<feature>.md`: title, file name and entry-point
count.

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
| A process that stops responding (hang) | `trace`: a stack sample of every thread | inspector pause or diagnostic report | Performance panel recording | py-spy dump | `jcmd` thread dump | dotnet-stack | goroutine dump | `gdb` thread backtrace / `spindump` |

Prefer a command that launches the app as a child of the profiler where the tool supports it: it
records only what the run started and needs no elevation. A tool that can only attach to a running
process goes through drive's attended `--attach` path.

Manuals, each record a pointer, as-of date and recheck trigger:

- Node.js CLI options (CPU profile, heap profile, heap snapshot signal):
  <https://nodejs.org/api/cli.html>. As of 2026-10-04. Recheck on a Node.js major release.
- Chrome DevTools Performance panel: <https://developer.chrome.com/docs/devtools/performance/reference>.
  Memory panel heap snapshots: <https://developer.chrome.com/docs/devtools/memory-problems/heap-snapshots>.
  As of 2026-10-04. Recheck when either page changes how a recording is saved.
- py-spy: <https://github.com/benfred/py-spy>. memray: <https://bloomberg.github.io/memray/>. As of
  2026-10-04. Recheck on a new major release of either.
- JDK `jcmd`: <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jcmd.html>. JDK `jfr`:
  <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jfr.html>. As of 2026-10-04. Recheck
  when the project moves to a newer LTS JDK.
- .NET diagnostics tools: <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-gcdump>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-stack>. As of 2026-10-04.
  Recheck on a .NET major release.
- Go profiling endpoints: <https://pkg.go.dev/net/http/pprof>; the pprof tool:
  <https://github.com/google/pprof>. As of 2026-10-04. Recheck on a Go minor release.
- Linux `perf record`: <https://man7.org/linux/man-pages/man1/perf-record.1.html>. As of
  2026-10-04. Recheck when the host kernel's perf version changes.
- heaptrack: <https://github.com/KDE/heaptrack>. GDB: <https://sourceware.org/gdb/documentation/>.
  As of 2026-10-04. Recheck on a new major release of either.
- macOS `sample`, `spindump` and `leaks`: the man pages on the host (`man sample`). Recheck on a
  macOS major release.

## Feature files

`features/<feature>.md`, written from the user's side:

| Section | Holds |
|---|---|
| `## Reset` | How to return the app's own data to a known state |
| `## States` | The states the feature can be in and what shows each |
| `## Entry points` | Where a user starts the feature |
| `## Drive` | The steps a user takes, one action per step |

## Driver commands

An optional `cli/` directory holds the project's own driver commands.

Each section is a pointer or a command, never a copied recipe: a recipe lives in one place and the
section names it.
