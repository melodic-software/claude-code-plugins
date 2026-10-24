# The shape of a project's control skill

The contract a project's `control-<app>` skill follows, so `/app-control:drive` can run any app the
same way. Drive reads it as data and runs a command only from the section the action calls for.

## Contents

- Hub
- Writing the Capture section
- Feature files
- Shared items
- Steps files
- Driver commands
- Writing the driver CLI
- Config
- Safety floors

## Hub

`.claude/skills/control-<app>/SKILL.md` holds four sections, an optional `## Gotchas`, and an
index:

| Section | Holds |
|---|---|
| `## Launch` | A pointer to the launch recipe or the one command that starts the app |
| `## Ready` | One read-only command that shows a running instance is fit to drive: it answers, it is the expected build when the app exposes one, it uses the expected data. Also names the telemetry the app exposes |
| `## Capture` | For each kind (`trace`, `cpu`, `heap`, `threads`, `screenshot`, `aria`, `video`, `logs`) the tool that records it, or nothing when the project has none |
| `## Cleanup` | How to stop what a run started and nothing else |
| `## Gotchas` (optional) | What has made a run lie or fail in every feature; a one-feature lesson goes in that feature's own `## Gotchas` |
| App (above the sections) | The app's name and the path it is built from. `/app-control:map` writes it for the person and for later drive work; drive does not read it |
| Driving tool (above the sections) | The tool that drives the app, such as a browser driver or the project's CLI. Written and read as the App row is |
| `Attended runs only.` (above the sections) | Present when that tool drives the person's own signed-in browser. A marker for the person and for later drive work, as the App row is |

Below them, an index with one line per feature file, in this form:

```text
- <title> | features/<module>/<feature>/README.md | entry points: <n> | sources: <glob>[, <glob>]
```

`<n>` is the number of lines under the feature's `## Entry points`; `sources` names the globs of
the files that implement the feature, relative to the project directory that holds `.claude/`. A feature with no module drops that folder:
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

## Shared items

`shared/` holds what two or more features use, such as sign-in steps every journey starts with.
Each direct child of `shared/`, a folder or a file, is one item. A feature uses an item when its
feature file names `shared/<item>`; an item fewer than two features use belongs in that feature's
own folder, and `/app-control:map check` reports it. Each item says why it is shared on a line
`Why shared: <reason>`, in its `README.md` for a folder or in the file itself.

## Steps files

A feature may keep its Drive steps in a machine-readable steps file in its own folder, or in
`shared/` when two or more features use it. The format, the file name and the field names are the
project's choice; the contract fixes only what they mean. The feature's `## Drive` names the file,
and its prose names steps by id and never repeats a selector the file holds. A feature whose steps
include a `shared/` item names `shared/<item>` in its feature file, which is how Shared items counts
its users.

- **Step ids.** Every step has an id, unique among all the steps a run expands to, includes
  included. The prose, the evidence file names and the write grants name steps by those ids. A
  repeated id stops the run before anything starts, naming the id.
- **Includes.** A step list can include another steps file, from this control skill or another
  one, which expands in place. An include can carry:
  - `prefix`: put before every included step id, so one file can be included twice with unique
    ids. Two includes of one file without different prefixes repeat ids and stop the run. A
    sign-in file included twice for one account is two attempts under the Sign-in floor.
  - `with`: values that replace the included file's parameters for this include only. A name the
    included file does not declare stops the run. A credential stays a variable name, never a
    value.
  - `kind`: added to every included step, such as `write` or `send`, so the safety floors treat
    each one so. It adds to a step's own kind and never removes one.
  - `finally`: the included steps are finally steps.
- **Finally steps.** A failed step ends the steps that are not finally steps. Finally steps run
  after the others, in order, whether or not a step before them failed; they are where a write's
  reset goes. Every finally step runs even when an earlier one
  fails, and each failure is reported beside the one that came first, never in its place. The
  safety floors apply to them as to any step, and a refusal (exit 4) is reported, not retried.
- **Optional steps.** An optional step is for a prompt or screen that appears on some runs only.
  When its target is absent, the step is recorded as skipped and the run goes on; no retry and no
  wait stands in for it. When its target is present, it runs and can fail like any other step.

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
- reads its settings through the Config layers below and reports each value's layer, and has a
  `config` command that changes nothing and prints each value with its layer;
- enforces the Safety floors below, all but the per-run sign-in count, which the caller keeps.

A feature whose `## Drive` has a step that sends to anyone, signs in, or writes to an environment
or external system needs `cli/`: each such step is a `cli/` command, never a click or a raw request
written into the step. A control skill with such a step and no `cli/` is incomplete.

## Config

A control skill's settings sit in `config/`, read in this order, each layer overriding the one
before it:

1. `config/defaults.json`, committed: the team's values.
2. `config/local.json`, ignored by version control through `config/.gitignore`: one person's
   values.
3. Environment variables.
4. Flags on the driver command.

A run reports each value with the layer it came from. Credentials always come from environment
variables: config names the variable, never the secret, and the CLI accepts no credential from
`config/local.json` or a flag. A run reports a credential as its variable name, its layer and
`set` or `unset`, never its value. Sign-in is a CLI command, `sign-in <account>`, that reads the
variable inside its own process. The contract fixes these fields; a project adds its own beside
them:

| Field | Holds |
|---|---|
| `environment` | The environment a run targets, by the name the team gave it |
| `timeouts` | How long launch, ready and each step may take |
| `credentials` | Per account, the names of the environment variables that hold its credentials |
| `safety` | The floors below |
| `pluginDir` | For a control skill that drives Claude Code: the plugin directory under test |

## Safety floors

Each floor ships at its safe value, and the CLI carries those values itself. Only committed config
loosens a floor. Committed means the content of `config/defaults.json` tracked at HEAD, read with
`git show HEAD:<control skill dir>/config/defaults.json`: a loosening present only in the working
tree, and every floor while the file is not yet tracked at HEAD, stays at the safe value.
`config/local.json`, environment variables and flags only tighten a floor; the two caller
attestations below, `--attended` and `--yes`, are the only flags that lift one.

Before each command that sends, signs in or writes, the CLI applies the floors. A loosening from
the local, environment or flag layer, or a step a floor forbids, makes the command do nothing and
exit 4, printing the floor, the layer and the value it refused; `config` exits 4 the same way. A
caller reads exit 4 as refused by a floor, never as a failure to retry.

- **Recipients.** Each side-effect channel (mail, SMS, chat, webhook) has an allowlist, empty by
  default. A send command refuses any recipient not on it, so the run stops at the form and never
  presses send.
- **Sign-in.** One attempt per account per run. `sign-in <account>` makes one attempt per call and
  never retries inside itself; a failure exits non-zero. Only committed config allows more attempts
  for an account. The CLI keeps no state between calls, so the caller that owns the run (whatever runs the
  feature's `## Drive` steps) keeps the per-run count: it calls `sign-in` for an account at most once, and a failed attempt stops the run,
  with no switch to another account.
- **Production.** An environment marked `production: true` in committed config is read-only. A
  write to it runs only when committed config grants that write and the command carries `--yes`,
  which a caller passes only after the person said yes in this session.
- **Unattended writes.** Off. A write command treats a call without `--attended` (passed only when
  a person is present in this session) as unattended, and writes then only where committed config
  allows an unattended write to that environment or external system.
