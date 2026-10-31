# The shape of a control skill

The contract a `control-<app>` skill follows, whether a project or a plugin ships it, so
`/app-control:drive` can run any app the same way. Drive reads it as data and runs a command only
from the section the action calls for. Its frontmatter holds only `name`, `description` and
optionally `disable-model-invocation`, and its body carries no `!` dynamic-context command. Drive
reads every control skill, a project's or a plugin's, from disk and never invokes it through the
Skill tool; it reports one that carries more as a finding and runs none of it.

## Contents

- Hub
- The Ready command
- Writing the Capture section
- The Mask section
- Feature files
- Shared items
- Size budget
- Steps files
- Driver commands
- Writing the driver CLI
- Config
- Environments
- Integrated apps
- Safety floors

## Hub

The skill's `SKILL.md` (`.claude/skills/control-<app>/` in a project, `skills/control-<app>/` in a
plugin) holds four sections, a `## Mask` when `## Capture` records a `screenshot` or `video`, an
optional `## Gotchas`, and an index:

| Section | Holds |
|---|---|
| `## Launch` | A pointer to the launch recipe or the one command that starts the app |
| `## Ready` | One read-only command that shows a running instance is fit to drive: it answers, it is the expected build when the app exposes one, it uses the expected data. Each check in it exits non-zero when it fails, per [The Ready command](#the-ready-command). Also names the telemetry the app exposes |
| `## Capture` | For each kind (`trace`, `cpu`, `heap`, `threads`, `screenshot`, `aria`, `video`, `animation`, `logs`) the tool that records it, or nothing when the project has none; one row per tier (such as `browser` and `server`) when the kind records differently on each |
| `## Cleanup` | How to stop what a run started and nothing else |
| `## Mask` | What a `screenshot` or `video` capture hides, and the values drive looks for in it afterward, per [The Mask section](#the-mask-section). Required when `## Capture` records either kind |
| `## Gotchas` (optional) | What has made a run lie or fail in every feature; a one-feature lesson goes in that feature's own `## Gotchas` |
| App (above the sections) | The app's name and the path it is built from. `/app-control:map` writes it for the person and for later drive work; drive does not read it |
| Driving tool (above the sections) | The tool that drives the app, such as a browser driver or the project's CLI. Written and read as the App row is |
| `Attended runs only.` (above the sections) | Present when that tool drives the person's own signed-in browser. A marker for the person and for later drive work, as the App row is |
| Integrated apps (above the sections) | One line per integrated app, per [Integrated apps](#integrated-apps), or none |

Below them, an index with one line per feature file it indexes, in this form:

```text
- <title> | features/<module>/<feature>/README.md | entry points: <n> | sources: <glob>[, <glob>]
```

`<n>` is the number of lines under the feature's `## Entry points`; `sources` names the globs of
the files that implement the feature, relative to the project directory that holds `.claude/`,
or, for a plugin control skill, to the root of the repository under verification. In a glob, `**`
matches across `/`, `*` and `?` match within one path segment, and every other character matches
itself; [`scripts/affected_features.py`](../scripts/affected_features.py) fixes this syntax, and
`/app-control:drive affected` runs it. A control skill present that matched no changed file
reports `control skill present, <n> files unmatched`. A feature with no module drops that folder:
`features/<feature>/README.md`.

Each folder level that has a `README.md` indexes the level below it. A module folder may hold its
own `README.md`, whose `## Sub-features` points to each feature folder under it; the hub's index
then names that `README.md` in place of a line per feature under the module. The module
`README.md` is a feature file with all six sections of [Feature files](#feature-files). Its
`## Entry points` repeats each entry point of the features under it, one line each, so the hub
line keeps the form above: its `<n>` is the number of lines under the module `README.md`'s own
`## Entry points`, which is the sum of the features' entry points, and its `sources` is the union
of their globs, so a changed file under any of them still matches a hub line. Each feature's own
`README.md` is the source of truth for its entry points: where the module `README.md`'s copy
disagrees with a feature's, the module copy is wrong and is rewritten from the features. The module
`README.md`'s `## Sub-features` holds one index line per feature under it, in the form above with
that feature's own path, count and globs. A caller that maps a changed file to features reads the
hub's lines, and for a matched module line reads the module `README.md`'s `## Sub-features` lines
too: the file maps to each feature whose own line's `sources` match it, and that line's path gives
the feature id (`features/auth/sign-in/README.md` is `auth/sign-in`). A module with no
`README.md`, like a small app with no modules, keeps a hub index line per feature.

A control skill can instead be a command file named `control-<app>`. The command file is the hub:
it holds the sections and the index. Its commands folder is the top-level folder it loads from: a
project's `.claude/commands/`, a skills-folder plugin's or a plugin's `commands/`, or the folder a
plugin manifest's `commands` key names. Its base
directory is `control-<app>/` in that commands folder's parent, whatever subfolder or file name
the command file has: a command file under `<base>/commands/` keeps its features at
`<base>/control-<app>/features/<id>/README.md`, where `<base>` is, for example, `.claude`,
the skills-folder plugin's folder or the plugin root. A command file the manifest's `commands` key
names as a file, directly or as a map entry's `source`, has no commands folder: its base directory
is `control-<app>/` in the plugin root wherever the file sits, so a plugin-root
`./control-shop.md` keeps its features at `<plugin root>/control-shop/features/<id>/README.md`,
inside the plugin. The base directory stands in for the skill
folder everywhere this contract names one, so `features/`, `shared/`, `cli/`, `config/` and steps
files sit there and the index paths resolve there. Every Markdown file under a commands folder,
in a subfolder too, loads as a command, so a feature file there would be one a model or a person
could invoke; one folder per command also keeps two commands in one commands folder from sharing
one `features/` tree.

## The Ready command

Drive and `/testing:run-e2e` read the Ready command's exit status as the verdict, so each check in
it must exit non-zero when the thing it checks is wrong. A listing (`docker ps`, `kubectl get pods`)
exits 0 when its filter matches nothing and it prints no rows, and exits 0 just the same when it
prints another app's row. A `kubectl get` that names an object (`kubectl get deploy/shop`) is not
a listing: it exits non-zero when the object is missing. End each listing with `grep -q` on the row the app's own instance prints,
never with the listing alone. A Ready with a url placeholder runs without a shell
([Environments](#environments)), where `|` and `&&` are plain arguments: put the listing check in a
`cli/` command or a script that exits non-zero itself, and name that from Ready.
`/app-control:map check` reports a Ready command whose last stage is a bare listing, and map's
proof runs Ready once with the app stopped to show it exits non-zero.

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
| A process that stops responding (hang) | `threads`, a stack of every thread | n/a | not yet | py-spy dump | `jcmd <pid> Thread.print` | `dotnet-stack report -p <pid>` | not yet | `gdb -p <pid> -batch -ex 'thread apply all bt'` / not yet |
| An animation that feels off, or content that jumps when interrupted | `animation`, per-frame state | n/a | `/playwright:playwright` animation capture recipe | n/a | n/a | n/a | n/a | n/a |

Prefer a command that launches the app as a child of the profiler where the tool supports it: it
records only what the run started.

When the app's work runs on a server behind a browser, write a row per tier for each kind that records differently on each: a
browser profile of a server-rendered app mostly shows the client runtime. Drive records each tier's
row, one tool per tier, and the artifact name carries the tier. The server tier's rows record the
app's own process, never a wrapper shell's, through the runtime's diagnostics tools. Its `logs`
row may name the runtime's counters recorder, which saves counter values (such as CPU use, GC and
thread pool counts) over the run to a file, launching the app as its child: for .NET 5 or later,
`dotnet-counters collect --format json -o <file> -- <command>`, where `<command>` starts the app
itself (a self-contained executable or `dotnet exec <app.dll>`), never `dotnet run`, since the
tool records the first .NET process that connects to it. A counters file is not a sampled profile.

Write a `threads` command, and a `cpu` or `heap` command that targets a running process, with a
`<pid>` placeholder and no elevation prefix, and with `<file>` where the tool takes an output path;
with no `<file>`, the command's stdout is the capture. Drive fills in the launched pid only after
its pid check, on Linux only, and always takes the elevated route for `threads`.

A `## Capture` command never carries an elevation prefix (such as `sudo`, `doas` or `runas`). When
a capture needs root or administrator rights, elevate only the recorder against the app's pid, never
the app, and leave the elevation to drive's shown-script step. Drive treats an unprefixed command
that fails for lack of permission the same way: a shown script when interactive, blocked when
unattended. A command that launches the app as a child of the profiler is never elevated: when it
is denied, drive blocks it and names the narrowest grant that would allow it.

A `screenshot` or `video` command applies every `## Mask` line ([The Mask section](#the-mask-section))
to the capture, for example through the driving tool's screenshot mask option, and writes a
sidecar beside it: the artifact's file name plus `.txt` (`<artifact>.txt`, such as
`checkout-cart-02-screenshot.png.txt`), holding the text the capture still shows after masking,
and for a video the text of every frame. Read that text from the saved artifact itself, for example
by OCR of the image or of each frame, not from the page's DOM: a DOM extract misses text drawn in a
canvas, an image, an iframe, a shadow DOM or a video overlay. Drive scans the sidecar and nothing
else, so a capture is only as safe to publish as its sidecar is complete; a capture with a missing
or empty sidecar is never publishable.

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
- JDK `jcmd`, `Thread.print` included:
  <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jcmd.html#commands-for-jcmd>. As of
  2026-10-27. JDK `jfr`: <https://docs.oracle.com/en/java/javase/21/docs/specs/man/jfr.html#subcommands>.
  As of 2026-10-23. Recheck either when the project moves to a newer LTS JDK.
- .NET diagnostics tools:
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-trace#dotnet-trace-collect>,
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-gcdump#dotnet-gcdump-collect>.
  As of 2026-10-23. Recheck on a .NET major release. dotnet-stack:
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-stack#dotnet-stack-report>. As
  of 2026-10-27. Recheck on a .NET major release. dotnet-counters:
  <https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-counters#dotnet-counters-collect>.
  As of 2026-10-30. Recheck on a .NET major release.
- Go profiling endpoints: <https://pkg.go.dev/net/http/pprof#hdr-Usage_examples>; the pprof tool:
  <https://github.com/google/pprof>. As of 2026-10-23. Recheck on a Go minor release.
- GDB: `thread apply all`
  <https://sourceware.org/gdb/current/onlinedocs/gdb.html/Threads.html#thread-apply-all>; attaching
  by pid and running one command
  <https://sourceware.org/gdb/current/onlinedocs/gdb.html/File-Options.html#File-Options>; batch
  mode <https://sourceware.org/gdb/current/onlinedocs/gdb.html/Mode-Options.html#Mode-Options>. As
  of 2026-10-27. Recheck on a GDB major release.
- Linux `perf record`: <https://man7.org/linux/man-pages/man1/perf-record.1.html>. As of
  2026-10-04. Recheck when the host kernel's perf version changes.
- heaptrack: <https://github.com/KDE/heaptrack>. As of 2026-10-04. Recheck on a new major release.
- macOS `sample`, `spindump` and `leaks`: no Apple docs page covers their flags as of 2026-10-23,
  so read the man pages on the host (`man sample`). Recheck on a macOS major release, or when an
  Apple docs page starts to cover these tools' flags.

## The Mask section

A hub whose `## Capture` records a `screenshot` or `video` holds a `## Mask` with mask lines, one
per text the capture must hide, such as the signed-in account and usage lines:

```text
- <label> | <regex>
```

or, when the app shows no such text, the single line `none: <reason>`. Write each as a plain line
outside any fenced block, as the index lines are. An optional `values:` line
names where the literal values to look for come from at run time, comma-separated:
`config.<field>` for a config field read through [Config](#config), or a read-only `cli/` command
in a code span whose stdout is one value per line:

```text
values: config.account.email, `cli/shop whoami --org`
```

The mask lines are for the Capture commands, which apply them ([Writing the Capture
section](#writing-the-capture-section)). Drive's post-check does not read them: it scans each
sidecar for the `values:` values and a generic credential pattern, so a mask that missed a region
still fails the check. A value is a secret like a credential: a run never writes it to the report.
`/app-control:map check` reports a hub whose `## Capture` records a `screenshot` or `video` and
whose `## Mask` holds no mask line and no `none: <reason>`.

## Feature files

`features/[<module>/]<feature>/README.md`, written from the user's side, with these six H2
sections in this order:

| Section | Holds |
|---|---|
| `## Parts` | The distinct behaviors inside the feature, one short line each |
| `## Sub-features` | The states or branches inside this feature that have their own feature file, each a pointer to it, or `none` |
| `## Entry points` | Where a user starts the feature, one line each. Each line ends `driven` or `not driven: <reason>`, the reason naming what would make it drivable, such as a test account, a seeded record or a `cli/` command. A drive through one entry point proves only that one and never marks another `driven` |
| `## Reset` | How to return the app's own data to a known state |
| `## Drive` | The steps a user takes, one action per step |
| `## Gotchas` | What has made a run lie or fail before |

A feature is a goal a user comes to the app to reach, such as placing an order. A sub-feature is a
state or branch inside that goal, such as an order paid with a saved card, never a separate goal.
A state or branch with no feature file of its own is a line in `## Parts`. A module's `README.md`
is the one exception: its `## Sub-features` points to the module's features, each its own goal.

UI that differs by tenant or configuration, such as a control a setting turns off or a role
hides, is a named precondition in `## Drive`, stating the tenant, setting or role the steps need,
or a step whose selector matches every variant. A selector written against one tenant's UI fails
on the next tenant.

A feature's id is `<feature>`, or `<module>/<feature>` when it sits in a module folder. Drive
resolves an id, relative to the skill's base directory, to `features/<id>/README.md`, then to the
legacy `features/<id>.md`. The legacy
file keeps working as written, with its `## States` section, until someone regroups it.

## Shared items

`shared/` holds what two or more features use, such as sign-in steps every journey starts with.
Each direct child of `shared/`, a folder or a file, is one item. A feature uses an item when its
feature file names `shared/<item>`; an item fewer than two features use belongs in that feature's
own folder, and `/app-control:map check` reports it. Each item says why it is shared on a line
`Why shared: <reason>`, in its `README.md` for a folder or in the file itself.

When the project signs in once and saves the session for the features that follow (an auth
bootstrap, such as a test harness's setup step or a `cli/` command; drive runs none), that
bootstrap runs the mapped sign-in steps, from `shared/` or by reference from the integrated app
that owns sign-in, and never copies their selectors, so the sign-in selectors live in one place.
Each feature that runs on the saved session names that sign-in item in its feature file, which is
how Shared items counts its users.

A feature that signs out runs in a throwaway browser session, never in the session the bootstrap
saved: signing out there can end the saved session for every feature that runs after it. The
throwaway session signs in with an account no other feature in the run signs in with, or with a
second attempt committed config allows for that account under the Sign-in floor. When the driving
tool drives the person's own signed-in browser, a feature that signs out is
`not driven: needs a driving tool that opens its own browser session`.

## Size budget

Drive loads the hub, then one feature file per level of the id, on every run, so their size is a
cost every run pays. Counted in characters, newlines included, the way
`/skill-quality:check listing-budget` counts, at about 4 characters per token:

| File | Budget | About |
|---|---|---|
| Hub `SKILL.md` or command file | 16,000 characters | 4,000 tokens |
| Each feature file: a `README.md` under `features/` at any depth, module ones included, or a legacy `features/<feature>.md` | 4,000 characters | 1,000 tokens |

`/app-control:map check` reports a file over its budget, and create reports one it wrote. Over
budget is a warning, never a stop: move detail into a steps file, a `cli/` command or a
sub-feature, or group the hub's index by module.

Basis: the control skill measured in
<https://github.com/melodic-software/claude-code-plugins/pull/10697>. Its hub was 12,160
characters, 84% of them index lines at about 114 characters each, so 16,000 leaves room for about
33 more index lines. Its largest feature file was a module README at 3,317 characters (the
largest seeded feature was 1,588), so 4,000 clears it by a fifth. One drive load at the budgets is
at most 24,000 characters (hub plus a module and a feature file), against the 16,399 measured.

## Steps files

A feature may keep its Drive steps in a machine-readable steps file in its own folder, or in
`shared/` when two or more features use it. The format, the file name and the field names are the
project's choice; the contract fixes only what they mean. The feature's `## Drive` names the file,
and its prose names steps by id and never repeats a selector the file holds. A feature whose steps
include a `shared/` item names `shared/<item>` in its feature file, which is how Shared items counts
its users.

- **Step ids.** Every step has an id made of letters, digits, `-` and `_` only, prefix included,
  unique among all the steps a run expands to, includes included, and among all the steps in this
  control skill's own steps files. The prose and the evidence file names name a step by its
  expanded id; a write grant names it by its id in the owning file, without a prefix, per the
  Write grants floor. A repeated id, or one with any other character, stops the run before
  anything starts, naming the id.
- **Includes.** A step list can include another steps file of this control skill or of an
  integrated app's ([Integrated apps](#integrated-apps)), which expands in place. The included
  file's real path must sit inside the directory of the control skill that owns it; one outside it
  stops the run. An include can carry:
  - `prefix`: put before every included step id, so one file can be included twice with unique
    ids. Two includes of one file without different prefixes repeat ids and stop the run. A
    sign-in file included twice for one account is two attempts under the Sign-in floor.
  - `with`: values that replace the included file's parameters for this include only. A name the
    included file does not declare stops the run. A credential stays a variable name, never a
    value.
  - `kind`: added to every included step, such as `write` or `send`, so the safety floors treat
    each one so. It adds to a step's own kind and never removes one. The run passes it to each
    included step's `cli/` command as `--kind <kind>`, and blocks an included step that is not a
    `cli:` step when the include adds `write` or `send`, since no CLI can hold it to that kind.
  - `finally`: the included steps are finally steps.
- **Finally steps.** A failed step ends the steps that are not finally steps. Finally steps run
  after the others, in order, whether or not a step before them failed; they are where a write's
  reset goes. Every finally step runs even when an earlier one
  fails, and each failure is reported beside the one that came first, never in its place. The
  safety floors apply to them as to any step, and a refusal (exit 4) is reported, not retried. A
  failed sign-in ends the other steps the same way; a finally step that would sign in again for
  that account is refused under the Sign-in floor and reported as blocked.
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

- prints one JSON document on stdout under `--json`, naming the environment it ran against, and
  progress on stderr;
- rejects an unknown flag, a repeated step id, or an app, environment or feature id that does not
  exist, before it starts anything; a write whose `--step` key has no grant is refused by the
  Write grants floor, not rejected here;
- records the app's own pid, not a wrapper shell's;
- reads its settings through the Config layers below and reports each value's layer, and has a
  `config` command that changes nothing and prints each value with its layer;
- enforces the Safety floors below, all but the per-run sign-in count, which the caller keeps;
- accepts `--kind write` and `--kind send` on every command, which only tightens: the command is
  then held to that kind's floors as well as its own;
- loads code only from inside its control-skill folder, plus dependencies pinned by a lockfile
  inside that folder that carries an integrity hash for each and names no file, path or link
  dependency. It installs them outside the folder, into a new directory for each run, with the
  ecosystem's frozen install, which checks every hash (the install form in
  `docs/contracts/on-demand-dependencies/README.md` in the marketplace repository); an install
  kept between runs is code the pin check never sees;
- writes nothing inside its control-skill folder (no installed dependencies, bytecode, caches or
  temp files), and turns bytecode off itself (for Python, `-B` or `sys.dont_write_bytecode = True`
  before any import), so the folder stays exactly the pinned tree and the untracked check in
  [Integrated apps](#integrated-apps) (Checkout off the pin) does not stop a second run.

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
| `environment` | The environment a run targets, by name; any layer may select one |
| `environments` | The environment entries, committed only, per [Environments](#environments) |
| `checkouts` | Per integrated app in another repository, the path of its local checkout, per [Integrated apps](#integrated-apps) |
| `pins` | Per integrated app in another repository, the full commit id its checkout must hold, committed only, per [Integrated apps](#integrated-apps) |
| `timeouts` | How long launch, ready and each step may take |
| `credentials` | Per account, the names of the environment variables that hold its credentials |
| `safety` | The floors below |
| `pluginDir` | For a control skill that drives Claude Code: the plugin directory under test |

## Environments

An environment's targets come only from committed config: the `environments` field of
`config/defaults.json` at HEAD, read the way Safety floors reads it. The local, environment and
flag layers may select an environment by name through `environment`, never add or redefine one.
`environments` and `pins` are committed-only fields: a local, environment or flag layer that sets
either, or any field inside one (an entry's `writes` and `systems` included), makes the CLI do nothing and exit 4, printing the layer and the
field, and `config` exits 4 the same way. Selecting a name that is not an entry at HEAD is an
unknown environment id.

Each entry, keyed by the name the team gave it, may hold:

| Field | Holds |
|---|---|
| `url` | Where the app answers in this environment |
| `services` | Per dependency service a journey crosses: its `url` and an optional read-only `ready` command, or `app` and `environment` naming an integrated app's environment, whose `url` is the service's url and whose ready check is that app's `## Ready` filled with that url |
| `extends` | Another entry in the same file whose fields this one starts from; its own fields replace them one by one, and `services` merge by name |
| `writes` | Per write, keyed by step id (or `cli/` command for a feature without a steps file), the key the caller passes as `--step` per the Write grants floor: `never`, `attended` or `unattended`. A write not listed has no grant |
| `systems` | Per external system a step writes to in this environment, by name: a `writes` map of the same shape |
| `production` | `true` marks the environment production, per the Production floor |

An `extends` naming no entry, or a chain that loops, is rejected before anything starts. An entry
that extends a production entry is production too; it cannot clear the mark.

A `## Launch` or `## Ready` command names these urls by placeholder: `<environment url>` for the
selected entry's `url`, `<<service> service url>` for a dependency service's. The run splits the
command into arguments first, fills each placeholder as exactly one argument, and runs the command
without a shell. The value must parse as an `http` or `https` URL and hold no whitespace, no
control character and none of `$`, `` ` ``, `'`, `"`, `\`, `;`, `|`, `<`, `>`, `&`, `(`, `)`, `%`
and `^`; a value that does not, or a placeholder that is not a whole argument, stops the run
before it launches anything, naming the placeholder and the value. A command with a placeholder
whose program is a `.cmd` or `.bat` file stops the run the same way, since Windows runs those
through a shell.

A `## Launch` command may also name `<changed files>`, such as to pass a diff to a `cli/` command
that loads the plugin folders those files sit in. It is a whole argument that expands to one
argument per changed file, read from the `affected.json` an earlier `/app-control:drive affected`
wrote into the same run directory: its features' `matched_files` and its `unmatched_files`, each a
path relative to the repository root, each once, and only those that exist in this checkout. With
none left it expands to no argument. A path that is absolute, has a `..` segment, starts with `-`
or holds a character the url rule above refuses stops the run before launch, naming the
placeholder and the path, and so does a `<changed files>` with no `affected.json` in the run
directory.

## Integrated apps

An integrated app is a system whose pages a journey crosses, such as a separate identity server.
It gets its own control skill, in the repository that builds it, owning its steps, Launch and
environments; this control skill never copies them. A journey belongs to the control skill of the
app where the user starts and ends it: the pages it crosses in an integrated app are steps that
app's control skill owns, included by reference. Every service the journey depends on, each
integrated app included, is a dependency service in the selected environment's `services`
([Environments](#environments)): a precondition the run's Ready checks before driving. The hub
lists each integrated app above the sections:

```text
- <app> | control-<app> | repository: <repository, or this one>
```

- **Include by reference.** A steps-file include names `<app>:<path>`, a steps file inside that
  app's control skill, and expands as any include does. An included `cli:` step runs the owning
  app's `cli/`, from its checkout, with that app's config layers, never this control skill's, and
  with an environment holding only `PATH`, `HOME`, the locale variables (`LANG`, `LC_*`),
  `GIT_NO_REPLACE_OBJECTS=1` and the credential variables that app's committed config names,
  leaving out any name this control skill's own `credentials` lists and any of `PATH`, `HOME`,
  `BASH_ENV`, `NODE_OPTIONS`, `LD_*`, `DYLD_*`, `PYTHON*` and `GIT_*`. The run passes it `--environment` with
  the `environment` of the selected entry's service for that app, stops before launching when no
  such service exists, and stops when the command's `--json` names another environment.
- **Checkout.** For an app in another repository, `checkouts.<app>` holds the path of its local
  checkout, relative to the project directory the Hub index's `sources` resolve against. It is
  one person's value, from any layer; it says where code is, not where an environment is, so the
  committed-only rule above does not apply.
- **Pin.** For the same app, `pins.<app>` in this control skill's committed config holds the full
  commit id (40 or 64 lowercase hex characters) of that app's control skill this one was written
  against; a ref name or a short id is not a pin. `/app-control:map` writes a pin only after
  `git -C <checkout> fetch <the hub line's repository URL> HEAD` and
  `git -C <checkout> merge-base --is-ancestor <sha> FETCH_HEAD` show the commit is on that
  repository's default branch, and reports the commit's subject; that fetch may write the
  checkout's objects and `FETCH_HEAD`, nothing else.
  That app's environments, floors and `writes` are read from its own committed config at the pin,
  `git -C <checkout> show <sha>:.claude/skills/control-<app>/config/defaults.json`.
- **Missing checkout.** When the setting is unset, its path does not exist, or the path holds no
  `.claude/skills/control-<app>/SKILL.md`, the run stops before launching anything and prints the
  setting's name and the repository to clone.
- **Checkout off the pin.** After that check, before launching anything, and again right before
  each included `cli:` call, before launching that app and before running its `## Ready`, the run
  stops unless all of these hold
  for `<dir>`, that app's `.claude/skills/control-<app>/`:
  - `pins.<app>` is set at HEAD and is 40 or 64 lowercase hex characters, checked before any git
    command;
  - `git cat-file -e <sha>^{commit}` succeeds;
  - `git diff --quiet <sha> HEAD -- <dir>` exits 0, so that app's CLI, which reads its floors at
    its own HEAD, reads the pinned ones;
  - every entry `git ls-files -v -- <dir>` prints is tagged `H`, so no skip-worktree,
    assume-unchanged or other index flag hides a change;
  - every path in `git ls-tree -r <sha> -- <dir>` exists, and every file found by walking `<dir>`
    is that app's `config/local.json` or a path in that tree whose `git hash-object --no-filters`
    equals the tree's blob id, as is or after turning CRLF into LF (the only normalization); a
    symlink must equal the tree's link text and resolve inside `<dir>`;
  - no path in `<dir>` has a `filter` attribute (`git check-attr filter`).

  Each git command runs as `git --no-replace-objects -C <checkout> -c core.fsmonitor=false`, with
  every `GIT_*` environment variable unset and `--end-of-options` before a revision. The check
  trusts the checkout's object store: it proves the folder equals the pinned commit as that store
  records it. When `pins.<app>` is unset
  the run prints the setting's name and to commit `pins.<app>`, for example through
  `/app-control:map`; otherwise it prints the setting's name, the pinned SHA and
  `fetch or check out`. The run passes no revision to that app's CLI; this check is what makes its
  config, floors, steps and `cli/` the pinned ones. [`scripts/verify_pin.py`](../scripts/verify_pin.py)
  implements this check. `python3 -I scripts/verify_pin.py <checkout> <app> <sha>`, where `<sha>`
  is `pins.<app>` at HEAD or an empty string when it is unset, exits 0 when every condition holds
  and otherwise exits non-zero, printing the message above and the condition that failed.
- **Floors.** An included step runs under the owning app's committed floors, enforced by its CLI.
  This control skill cannot loosen them, and tightens an included step only through the include's
  `kind` or by not including it. The caller's per-run sign-in count spans both apps.
- **Launch.** When the selected environment runs the integrated app locally, the run launches it
  with that app's Launch and stops it at cleanup, keeping one launch record and one log per app.
  This control skill's Launch takes the app's url through a `<<service> service url>` placeholder,
  filled per [Environments](#environments).

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
- **Write grants.** Every write command takes `--step <id>`. Each key binds to one command: a
  step id to that step's `cli:` command in the control skill's own steps files at HEAD
  (`git show HEAD:`), and a key naming no step only to the `cli/` command of that name. No step id
  equals a `cli/` command name, and a step's `cli:` holds none of the reserved flags
  `--environment`, `--step`, `--kind`, `--json`, `--attended` and `--yes`. A binding matches the
  command being run when, leaving out the reserved flags and their values, every other argument
  matches in count and order, a `{parameter}` matching any one argument that does not start with
  `-`. The CLI refuses unless the `--step` key is listed in the committed `writes` of the selected
  environment, or of the `systems` entry it writes to, and its binding matches; it then applies
  the strictest grant among every listed key whose binding matches (`never`, then `attended`,
  then `unattended`). A missing, unknown or unlisted `--step`, a binding that does not match,
  `never`, and `attended` without `--attended` are refused.
- **Production.** An environment marked `production: true` in committed config is read-only. A
  write to it runs only when committed config grants that write's `--step` key (`attended` or
  `unattended` in its `writes`) and the command carries `--yes`, which a caller passes only after the person said yes in
  this session. `--yes` without `--attended` is refused, so no config turns on an unattended
  production write.
- **Unattended writes.** Off. A write command treats a call without `--attended` (passed only when
  a person is present in this session) as unattended, and writes then only where committed config
  marks that write's `--step` key `unattended` for that environment or external system.
