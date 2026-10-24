# The shape of a project's control skill

The contract a project's `control-<app>` skill follows, so `/app-control:drive` can run any app the
same way. Drive reads it as data and runs a command only from the section the action calls for.

## Contents

- Hub
- Writing the Capture section
- Feature files
- Driver commands
- Writing the driver CLI
- Config
- Safety floors

## Hub

`.claude/skills/control-<app>/SKILL.md` holds four sections and an index:

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
resolves an id to `features/<id>/README.md`, then to the legacy `features/<id>.md`. The legacy
file keeps working as written, with its `## States` section, until someone regroups it.

## Driver commands

An optional `cli/` directory holds the project's own driver commands.

Each section is a pointer or a command, never a copied recipe: a recipe lives in one place and the
section names it.

## Writing the driver CLI

Guidance for whoever writes `cli/`. When `/developer-experience:build-cli` is installed, write the
CLI through it. Otherwise write a script in the language the repository already uses, with a
`cli/README.md` listing each command, its flags and its exit codes. Either way the CLI:

- prints one JSON document on stdout under `--json`, and progress on stderr;
- rejects an unknown flag, a repeated step id, or an app, environment or feature id that does not
  exist, before it starts anything;
- records the app's own pid, not a wrapper shell's;
- reads its settings through the Config layers below and reports each value's layer.

## Config

A control skill's settings sit in `config/`, read in this order, each layer overriding the one
before it:

1. `config/defaults.json`, committed: the team's values.
2. `config/local.json`, ignored by version control: one person's values.
3. Environment variables.
4. Flags on the driver command.

A run reports each value with the layer it came from. Credentials come from environment variables
by default: config names the variable, never the secret. The contract fixes these fields; a project
adds its own beside them:

| Field | Holds |
|---|---|
| `environment` | The environment a run targets, by the name the team gave it |
| `timeouts` | How long launch, ready and each step may take |
| `credentials` | Per account, the names of the environment variables that hold its credentials |
| `safety` | The floors below |
| `pluginDir` | For a control skill that drives Claude Code: the plugin directory under test |

## Safety floors

Each floor ships at its safe value. Only `config/defaults.json` loosens one; `config/local.json`,
environment variables and flags only tighten it, and a run reports a loosening from those layers as
refused.

- **Recipients.** Each side-effect channel (mail, SMS, chat, webhook) has an allowlist, empty by
  default. A step that would send to anyone not on it stops at the form and never presses send.
- **Sign-in.** One attempt per account per run. A failed attempt stops the run, with no retry and
  no switch to another account. Only committed config allows more attempts for an account.
- **Production.** An environment marked `production: true` in committed config is read-only. An
  attended run writes to it only when committed config grants that write and the person says yes in
  this session.
- **Unattended writes.** Off. An unattended run writes to an environment or external system only
  where committed config allows it.
