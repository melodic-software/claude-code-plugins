# The shape of a control skill

The contract a `control-<app>` skill follows, whether a project or a plugin ships it, so
`/app-control:drive` can run any app the same way. Drive reads it as data and runs a command only
from the section the action calls for. Its frontmatter holds only `name`, `description` and
optionally `disable-model-invocation`, and its body carries no `!` dynamic-context command. Drive
reads every control skill, a project's or a plugin's, from disk and never invokes it through the
Skill tool; it reports one that carries more as a finding and runs none of it.

## Contents

- Hub
- The launch model
- The Ready command
- Writing the Capture section
- The Mask section
- Feature files
- Lessons
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
| `## Launch` | A pointer to the launch recipe or the one command that starts the app from empty data, and the launch model lines, per [The launch model](#the-launch-model) |
| `## Ready` | One read-only command that shows a running instance is fit to drive: it answers, the port it answers on belongs to the instance the run drives, the credentials the run uses are valid, it is the expected build when the app exposes one, it uses the expected data. Each check in it exits non-zero when it fails, per [The Ready command](#the-ready-command). Also names the telemetry the app exposes |
| `## Capture` | For each kind (`trace`, `cpu`, `heap`, `threads`, `screenshot`, `aria`, `video`, `animation`, `logs`) the tool that records it, or nothing when the project has none; one row per tier (such as `browser` and `server`) when the kind records differently on each; optionally a `frames` row, per [Writing the Capture section](#writing-the-capture-section) |
| `## Cleanup` | How to stop what a run started and nothing else |
| `## Mask` | What a `screenshot` or `video` capture hides, and the values drive looks for in it afterward, per [The Mask section](#the-mask-section). Required when `## Capture` records either kind |
| `## Gotchas` (optional) | What has made a run lie or fail in every feature; a one-feature lesson goes in that feature's own `## Gotchas`, per [Lessons](#lessons) |
| App (above the sections) | The app's name and the path it is built from. `/app-control:map` writes it for the person and for later drive work; drive does not read it |
| Driving tool (above the sections) | The tool that drives the app, such as a browser driver or the project's CLI. Written and read as the App row is |
| `Attended runs only.` (above the sections) | Present when that tool drives the person's own signed-in browser. A marker for the person and for later drive work, as the App row is |
| Integrated apps (above the sections) | One line per integrated app, per [Integrated apps](#integrated-apps), or none |
| Driving conventions (above the sections, optional) | How every run drives this app, per [Driving conventions](#driving-conventions) |

### Driving conventions

A hub may state, above its sections, the conventions every drive of the app follows, so each agent
drives it the same repeatable way. Create writes these three, adjusted to the app:

- Start from the baseline: run each feature's `## Reset`, or the launch from empty data
  ([The launch model](#the-launch-model)), before its first step, never from the state an earlier
  run left.
- Name a control by its role and accessible name, or by its label, test id (such as
  `[data-test=basket]`), prompt text or route, never by a styling or structural CSS selector, a
  screen coordinate or tab order, unless the app exposes nothing else.
- Write literal commands: the exact command, handle and path the run types, never an example a
  reader has to adapt. The placeholders this contract defines (`<environment url>`,
  `<<service> service url>`, `<changed files>` and a steps file's parameters) stay placeholders.

`/app-control:map check` does not require them, and a hub without them stays valid. Basis: the
stable-handle and real-command rules of
<https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/SKILL.md>
(read 2026-11-13).

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

## The launch model

`## Launch` starts the app the way a user first meets it: from empty data, with the app's own
migrations run and its seed data loaded, ending in an instance a user could work in. Where the app
keeps data (a database, a data directory, a config folder), each run gets a new data directory of
its own, outside the checkout, and the launch points the app at it, never at the state an earlier
run or the person's own use left. `## Launch` records the model in plain lines outside any fenced
block:

```text
Data: <the per-run data directory, and the migrate and seed commands the launch runs>
Side by side: yes[, <how two instances stay apart, such as a port per run>]
Session: build once with <build command>; one isolated session per drive, <how>
```

- `Data: none: <reason>` when the app keeps no data, or when its data cannot start empty, the
  reason naming why (such as a signed-in account the run must reuse). A launch that cannot start
  from empty data says so here.
- `Side by side: no: <reason>` when two instances cannot run at once, such as on a fixed port or a
  lock on a shared file, so a caller runs one drive at a time.
- `Session:` for a short-lived command-line or terminal app, one that exits after each use: the run
  builds it once, then gives each drive its own session, with its own data directory and process,
  so one drive's state never reaches the next. A long-running server has no `Session:` line.

A hub whose `## Launch` hands off to the driving tool's still writes these lines itself. Every
value is the project's, kept in its control skill and config; the contract fixes only what the
lines mean. `/app-control:map check` reports a `## Launch` with no `Side by side:` or no `Data:`
line (`launch-model`); it cannot tell a short-lived app, so it does not check `Session:`. Basis:
the launch and readiness rules of pstack's `create-verification-skill`, as the
[upstream record](../../../docs/upstream/cursor-pstack.md) holds them.

## The Ready command

Drive and `/testing:run-e2e` read the Ready command's exit status as the verdict, so each check in
it must exit non-zero when the thing it checks is wrong. A listing, a command that prints the rows
its filter matches, exits 0 when the filter matches nothing and it prints no rows, and exits 0 just
the same when it prints another app's row. A command that names one object and exits non-zero when
that object is missing is not a listing. End each listing with `grep -q` on the row the app's own instance prints,
never with the listing alone. A Ready with a url placeholder runs without a shell
([Environments](#environments)), where `|` and `&&` are plain arguments: put the listing check in a
`cli/` command or a script that exits non-zero itself, and name that from Ready.
`/app-control:map check` reports a Ready command whose last stage is a bare listing, and map's
proof runs Ready once with the app stopped to show it exits non-zero.

Ready shows a user could use the instance, not only that something answers:

- **Port owner.** The port or socket Ready reaches belongs to the instance the run drives, the one
  it launched or an already running one it was handed (such as an attached pid): for example, the
  pid listening on the port is the one in drive's launch record or the attached pid, or a health
  field returns an instance id the launch set. Another process holding the port makes Ready exit
  non-zero.
- **Credentials.** Each credential the run uses is valid, shown by one read-only call that needs it
  (such as a `whoami` request through `cli/`), not only by its variable being set. A credential
  that can be checked only by signing in is checked at the run's sign-in step, under the Sign-in
  floor, never by Ready.

A check the app gives no way to make is written in Ready as `<check>: not exposed`, as
`build: not exposed` is, and drive reports it as a capability gap.

## Writing the Capture section

Guidance for the person or agent writing a control skill's `## Capture`; drive never reads this
guidance to pick a tool. Each symptom records one kind: a core pinned near 100% (spin) is `cpu`;
memory that keeps growing (leak) is `heap`, two snapshots minutes apart; UI that stutters or drops
frames (jank) is `trace` with CPU samples; a process that stops responding (hang) is `threads`, a
stack of every thread; an animation that feels off, or content that jumps when interrupted, is
`animation`, per-frame state. For each kind, name only a tool the repository already shows for it
(a script it runs, a doc that names it, or the tool's own config), and leave a kind with none
empty. Read the tool's current flags in its own manual before writing the command, since flags
change between releases.

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

`## Capture` may also hold a `frames` row: the command that writes a screen recording's frames as
still images, with `<recording>` and `<dir>` placeholders, so a recording, this run's or one a
person hands over, can be read frame by frame. It is not a capture kind. Drive's `ready` reports
whether this session can run it and read the images it writes; a hub with no `frames` row, or a
session that cannot read images, is a capability gap.

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

A `cli/` source may instead print exactly one line, `none: <reason>` with a reason that is not
empty, and exit 0: the source then resolves with no values, such as an account command run under
key auth, which has no signed-in account. Each source is judged on its own. A non-zero exit, empty
output, or any other line beside the `none:` line leaves that source unresolved.

A hub whose driving tool's own control skill holds the masks hands off instead: its `## Mask` holds
this single line and nothing else, as the hub's other sections hand off to the driving tool's:

```text
The driving tool's `## Mask`.
```

The target is the hub named on the hub's `Driving tool:` line: the first code span on that line, or
on the lines that continue it up to the next blank line, that holds a relative path ending in `.md`.
It resolves against the copy of the hub drive read, never the checkout under test: the project
directory holding that hub's `.claude/`, or, for a plugin hub, the repository its folder sits in.
Its real path must sit inside that directory, and under drive's `--trusted-root <dir>` inside
`<dir>`'s real path, so a checkout under test cannot supply its own masks or values source. The
target's `## Mask` is then the one in effect, and its `values:` sources resolve against the
target's own `config/` and `cli/`. A target that is missing, sits outside that directory, has no
`## Mask`, or hands off again cannot be read, and every capture of the run is `not-checked`.

The mask lines are for the Capture commands, which apply them ([Writing the Capture
section](#writing-the-capture-section)). Drive's post-check does not read them: it scans each
sidecar for the `values:` values and a generic credential pattern, so a mask that missed a region
still fails the check. A value is a secret like a credential: a run never writes it to the report.
`/app-control:map check` reports a hub whose `## Capture` records a `screenshot` or `video` and
whose `## Mask` in effect, the hand-off target's included, holds no mask line and no
`none: <reason>`, or whose hand-off target cannot be read.

## Feature files

`features/[<module>/]<feature>/README.md`, written from the user's side. It opens with an H1
title, the feature's name, and one paragraph saying what the feature is, then these six H2 sections
in this order:

| Section | Holds |
|---|---|
| `## Parts` | The distinct behaviors inside the feature, one short line each. A line may start with a short id in bold, such as `**P1.**`, that steps and evidence can name |
| `## Sub-features` | The states or branches inside this feature that have their own feature file, each a pointer to it, or `none` |
| `## Entry points` | Where a user starts the feature, one line each. Each line ends `driven` or `not driven: <reason>`, the reason naming what would make it drivable, such as a test account, a seeded record, a dev-only role switch or a `cli/` command. A drive through one entry point proves only that one and never marks another `driven` |
| `## Reset` | How to return the app's own data to a known state, run on a reused instance only per [Reset on a reused instance](#reset-on-a-reused-instance) |
| `## Drive` | The steps a user takes, one action per step, each with the result a user should observe, ending in a proof step ([Drive steps](#drive-steps)). It may open with a `Preconditions:` line ([Preconditions](#preconditions)) |
| `## Gotchas` | What has made a run lie or fail before, per [Lessons](#lessons) |

Create writes the title and paragraph, and may give Parts ids. `/app-control:map check` requires
neither: a feature file without them stays valid.

### Reset on a reused instance

A run performs a feature's `## Reset` on an instance it reuses only when the hub's `Data:` line
names a per-run data directory ([The launch model](#the-launch-model)), so the data it resets is
that run's own. With `Data: none: <reason>`, the data is not the run's own: the run does not
perform the Reset on the reused instance. It stops that instance as cleanup does and launches
fresh; where it cannot launch fresh (such as `Side by side: no` with another instance holding the
port), it blocks with the reason.

### Drive steps

Each step is one list item at the start of a line, a bullet or a number such as `1.`, that may
wrap onto indented lines. A step names three things: the user's action, the exact command or
handle it uses (a selector, a key, a URL or a `cli/` command), and, after `Result:`, what a user
should observe once it runs, as an output, a screen state, an exit code or a file state. The last
step is the proof step, labeled `**Proof.**`, which takes no action of its own. Its `Result:` is
the end state that proves the feature works, and its `Captures:` names the
[Capture](#writing-the-capture-section) kinds that show that end state:

```text
1. Open the cart: `click [data-test=basket]`. Result: the cart page lists one item.
2. **Proof.** Result: the cart page lists the added item at its price. Captures: aria, screenshot
```

A step and its result change together, so the result stays on its step; a feature has no
separate proof section. Preconditions and `Budget:` lines are not list items. A `## Drive`
that hands off to another feature or to a [steps file](#steps-files) has no steps of its own:
the steps there state their results. `/app-control:map check` reports a step with no `Result:`.

`## Drive` may end with performance budget lines, one per measure, in this form:

```text
Budget: <measure> | <source>
```

`<measure>` is a name of letters, digits, `-` and `_` that carries its unit, such as
`first_paint_ms`; `<source>` is the `## Capture` kind or the `cli/` command whose output gives the
value. The threshold is never written in the feature file: it is the config field
`budgets.<feature id>.<measure>` ([Config](#config)). Drive records the value it measured beside
the threshold and the layer the threshold came from, or `unset` when no layer sets it, and never
compares them; the caller judges. A legacy `features/<id>.md` takes the same lines. A performance
budget is not the [Size budget](#size-budget), which limits a file's length.

A feature is a goal a user comes to the app to reach, such as placing an order. A sub-feature is a
state or branch inside that goal, such as an order paid with a saved card, never a separate goal.
A state or branch with no feature file of its own is a line in `## Parts`. A module's `README.md`
is the one exception: its `## Sub-features` points to the module's features, each its own goal.

UI that differs by tenant or configuration, such as a control a setting turns off or a role
hides, is a state on the `Preconditions:` line ([Preconditions](#preconditions)), naming the
tenant, setting or role the steps need, or a step whose selector matches every variant. A selector written against one tenant's UI fails
on the next tenant.

A feature's id is `<feature>`, or `<module>/<feature>` when it sits in a module folder. Drive
resolves an id, relative to the skill's base directory, to the first of these that exists:

1. `features/<id>/README.md`;
2. the legacy `features/<id>.md`, which keeps working as written, with its `## States` section,
   until someone regroups it;
3. for an id `<module>/<part>`, the part named `<part>` under `## Parts` in the file `<module>`
   resolves to by 1 or 2. A Parts line names a part when it starts with a code span
   (`` `run-e2e`: ``), a bold id (`**P1.**`) or a word followed by `:` (`range:`), the markup and a
   trailing `.` or `:` dropped. Drive runs that file's `## Drive` for the part.

A part with a feature file of its own therefore resolves to that file. An id that matches none of
these, or names a part two Parts lines share, stops that feature, and drive names each path and
Parts section it looked in. `/app-control:map check` reports two Parts lines in one feature file
that name the same part.

### Preconditions

`## Drive` may open, before its first step, with one line naming each state that must hold before
the first step and that the feature's `## Reset` and the hub's `## Ready` do not already set, such
as a seeded record, an account in a role, a tenant setting or a file that must be absent:

```text
Preconditions: <state>; <state>
```

Write each state so a run can check it, never as a step. A feature with nothing to state leaves the
line out; `/app-control:map check` does not require it.

A run never passes by weakening the journey. When the data lacks a precondition the journey needs,
the step that needs it fails and is reported as failed, and the reason is a lesson for that
feature's `## Gotchas` ([Lessons](#lessons)); the steps, their results, the proof step and the `Preconditions:` line stay as
written. Weakening is dropping, skipping or reordering a step (an absent optional step, per
[Steps files](#steps-files), is not weakening), loosening a `Result:`, driving
another entry point in its place, or reaching the state through a test-only endpoint or an internal
setter instead of the user's path. A failed step has one of two causes, kept apart:

- **The control skill is wrong**: a handle or route that moved, or a state the steps need that the
  `Preconditions:` line does not name. Create and refresh fix the control skill.
- **The data lacks a precondition** the line names. No edit to the steps fixes it: the failure
  stands, and the data is fixed outside the steps, through `## Reset`, a seed or a test account.

### Step evidence

The evidence each kind of action needs:

| Action | Evidence |
|---|---|
| A UI end state | The proof step's `Captures:` names `aria` and `screenshot`, the screenshot with the app's identity visible, such as its name or URL. A hub whose `## Capture` names no `aria` tool, such as a terminal app's, names `screenshot` alone |
| A command line (a `cli/` command or any other command) | The command, its standard output, its standard error and its exit code. Drive records all four for every such step |
| A change to stored data | A read-only second view of the stored value: a later step that reads it back through a separate request, query or file read, never the app's own confirmation. The rule is `/testing:run-e2e`'s "Evidence the run reads back" |

Every artifact name carries the feature and the entry point it came from. A kind `## Capture` names
no tool for is a capability gap, never replaced by another kind. An entry point a run skipped is
never reported as proven through another entry point (`## Entry points` above).

Basis: the seed-data and evidence rules of
<https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/SKILL.md> and
the `Preconditions:` line and per-action proof of
<https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/references/feature-map-example/README.md>
(both read 2026-11-15).

## Lessons

A lesson is what a run learned about driving the app: a wait a step needs, a handle that lies, an
order that matters, a precondition the data lacked. `/app-control:map` is the only writer of a
control skill's `## Gotchas`, the hub's and each feature's. Every `/app-control:drive` run and
every `/debugging:debug` run lists the lessons it learned in its report, each as one
`/app-control:map refresh "<lesson>"` line, or says it learned none, and writes none into the
control skill. Refresh accepts a lesson handed in from such a report and places it by scope. A
lesson names a credential by its variable name, never its value.

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
and its prose names steps by id and never repeats a selector the file holds. Every step holds a
result: what a user should observe once it runs, with the meaning [Drive steps](#drive-steps)
gives it. The proof step belongs to the list a run expands to, not to each file: it is the last
step before the finally steps, kept in the feature's own steps file, so an included file needs
none. In the file it is a step with an id, a result and the capture kinds that show the end state,
and no action or command: the run performs nothing for it and reports it by its id, with the
captures it names, after the steps before it have run. A feature whose steps
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

Guidance for whoever writes `cli/`. When `/developer-experience:build-cli` is enabled, write the
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
  temp files), and turns bytecode off itself before it loads any code, so the folder stays exactly
  the pinned tree and the untracked check in
  [Integrated apps](#integrated-apps) (Checkout off the pin) does not stop a second run.

So agents can use it well, the CLI also has these traits, which create writes and
`/app-control:map check` does not require:

- a few composable commands, each doing real work, rather than many thin ones;
- `--dry-run` on every command that writes or sends: it checks its arguments and the floors as a
  real run would, prints what it would do, and does nothing. A dry run sits beside the
  [Safety floors](#safety-floors) and the Write grants, never in place of them: it grants no write,
  lifts no floor, and a command a floor refuses is refused under `--dry-run` too (exit 4). A dry
  run is trusted only once a run was seen to change nothing, since some still touch the network
  or open a browser: `cli/README.md` marks each command's dry run `trusted`, naming the run or test
  that showed it and what it watched stay unchanged (files, network calls, git refs, processes),
  or else `untrusted`. How to watch one is `/testing:run-e2e`'s "Watch what a dry run touches". A
  caller runs an `untrusted` dry run only where the real command may run;
- subcommands that reveal features gradually: `--help` lists the commands one line each, and
  `<command> --help` gives that command's flags;
- error messages that say what to do instead, such as the flag to add or the command to run first;
- rich `--help` text on every command: its flags, what it does and its exit codes.

Basis: the traits of a CLI agents use well in
<https://github.com/cursor/plugins/blob/main/pstack/docs/guide/06-verify-and-ship.md> (read
2026-11-13), all but its machine-readable output, which `--json` above already covers. The
dry-run trust mark: the Evidence rules of
<https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/SKILL.md>
(read 2026-11-15).

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
| `budgets` | Per feature id, per measure a feature's `Budget:` line names, the threshold, in the unit the measure's name carries, per [Feature files](#feature-files) |
| `credentials` | Per account, the names of the environment variables that hold its credentials |
| `safety` | The floors below |
| `pluginDir` | For a control skill that drives Claude Code: the plugin directory under test |

## Environments

An environment's targets come only from committed config: the `environments` field of
`config/defaults.json` at HEAD, read the way Safety floors reads it. The local, environment and
flag layers may select an environment by name through `environment`, never add or redefine one.
`environments` and `pins` are committed-only fields: a local, environment or flag layer that sets
either, or any field inside one (an entry's `writes`, `systems` and `sources` included), makes the CLI do nothing and exit 4, printing the layer and the
field, and `config` exits 4 the same way. Selecting a name that is not an entry at HEAD is an
unknown environment id.

Each entry, keyed by the name the team gave it, may hold:

| Field | Holds |
|---|---|
| `url` | Where the app answers in this environment |
| `services` | Per dependency service a journey crosses: its `url` and an optional read-only `ready` command, or `app` and `environment` naming an integrated app's environment, whose `url` is the service's url and whose ready check is that app's `## Ready` filled with that url |
| `extends` | Another entry in the same file whose fields this one starts from; its own fields replace them one by one, and `services` and `sources` merge by name |
| `writes` | Per write, keyed by step id (or `cli/` command for a feature without a steps file), the key the caller passes as `--step` per the Write grants floor: `never`, `attended` or `unattended`. A write not listed has no grant |
| `systems` | Per external system a step writes to in this environment, by name: a `writes` map of the same shape |
| `sources` | Per data source an agent can reach in this environment, by name: its `kind`, `where` and `read` level, and its optional `credential`, `grants` and `data`, per [Data sources](#data-sources) |
| `production` | `true` marks the environment production, per the Production floor |

An `extends` naming no entry, or a chain that loops, is rejected before anything starts. An entry
that extends a production entry is production too; it cannot clear the mark.

### Data sources

A data source is where an agent reads what the app did in an environment. Each `sources` entry
holds:

- `kind`: `logs`, `telemetry`, `database`, `tracker` (the work-item tracker that holds the app's
  reported defects) or `errors` (the error reporter);
- `where`: how to read it, as a path, a url or a read-only command;
- `read`: when a run may read it, on the same three levels as a write grant: `never`; `attended`,
  only with a person present in this session; `unattended`, with no one present too. An entry with
  no `read` reads as `never`.

An entry read with a credential also holds:

- `credential`: the name of the environment variable that holds it, per [Config](#config), never
  the secret;
- `grants`: how the credential's read-only grants were shown: a read-only command the consumer
  supplies that lists what the credential may do in the store and exits 0 only when it may change
  nothing; or `full-user-access` for a source that offers no scope control, where the credential
  carries everything its user may do and no read-only grant exists to show.

An entry may also hold `data`: the data category the source exposes, who may read it, and a
reference to the review that decided both (`category`, `readers`, `review`). The control skill
records that review; it does not perform it.

An entry with `grants: full-user-access`, with or without a `credential` (a signed-in session
counts), or with a `credential` and no `grants` or a `grants` command that does not exit 0, is
capped at `attended` whatever its `read` says, and ready names which of
the three applies. Basis: a read-only rule enforced only in the
agent's tool can be bypassed by the text the agent sends, so the guarantee rests on the store's
own grants, the stance ADR 0086 in the marketplace repository takes for its read tier.

An environment's sources are those left once `extends` is resolved, inherited ones included. Each of
the five kinds with no entry there is missing, the tracker and the error reporter included. `/app-control:drive ready` reports each
environment's sources with their read levels, each `credential` by variable name, each `data` field
and each cap, and lists the missing kinds. It runs each `grants` command where the entry's `read`
level allows a read in this run and reports its exit, or `not run` with that level; that command shows grants, not the source's
contents, and ready reads none of the sources. A caller reads a source only through its `where`
and only at its level after the cap. `/app-control:map` create and refresh write the entries;
`never` is the safe level, and only a person sets another.

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
