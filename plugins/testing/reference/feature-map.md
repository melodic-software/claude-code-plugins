# Feature map format

A feature map tells an agent how to exercise each user-facing feature of one application in a
consumer repository: where a user finds the feature, how a run drives it, and what goes wrong.
`/testing:map-features` writes it, `/testing:refresh-feature-map` keeps it current, and
`/testing:run-e2e` reads it to decide which entry points a change must be driven through.
`/verification:confirm` never reads the map; it reads run-e2e's per-entry-point report.

## Where it lives

The map is its own project skill directory in the consumer repository, at the resolved
`feature_map_dir` (default `.claude/skills/feature-map/`; the key is described in
`skills/run-e2e/context/e2e-config.md`). Agents in that repository find a project skill without a
pointer.

One directory holds one map. A repository with several apps keeps one app's map in the default
directory and each other app's in `.claude/skills/feature-map-<app slug>/` (the app's name through
the slug rule under File names). `/testing:run-e2e` and `/testing:refresh-feature-map` reach such a
map when the session prompt or their `--dir` names it, or when `feature_map_dir` in the overlay
`.claude/testing.local.yaml` points at it.

It never shares a directory with a launch recipe. `/run-skill-generator` owns
`.claude/skills/run-<name>/` and may regenerate it whenever the build or launch changes, and a
skill named `verify` at `.claude/skills/verify/SKILL.md` replaces the bundled `/verify` and can run
before every commit. So a location that is absolute, contains `..`, is the repository root (`.` or
`./`), holds a character outside `A-Z a-z 0-9 . _ - /`, or has a segment that starts with `run-` or
ends in `verify` is refused. So is `.claude/skills` itself (with or without a leading `./` or a
trailing `/`, in any letter case): the map is a project skill and needs its own directory under
`.claude/skills/`, not the skills root.

```text
.claude/skills/feature-map/
  SKILL.md                 the index
  start-a-timer.md         a feature file
  weekly-timesheet-export.md
```

## The index

The index is the map skill's `SKILL.md`. Its frontmatter carries a `description` naming the
application and saying to read the map before driving it, plus `disable-model-invocation: false`
so agents load it when they verify that app. The body holds these fields, each filled from what the
repository showed, never a placeholder:

| Field | What it holds |
|---|---|
| Application | The app's name and the directory it is built from. |
| Launch | The recipe that starts it: the repository's `run-<name>` skill by name, else the recorded `.claude/skills/verify/SKILL.md`, else the start path `/testing:run-e2e` uses (the documented start command or the orchestrator). The map points at the recipe; it never copies the recipe's steps. |
| Driver | The driver resolved when the map was written (`harness`, `run`, `playwright` or `chrome`) and the layer that supplied it. `chrome` adds the line `Attended runs only.` A `harness` that starts the app itself adds `The harness hosts its own instance.` |
| Doctor | One read-only command that says whether a running instance is fit to drive: it answers, it is the expected build, it uses the data this run expects. The build check applies when the app exposes a build identifier; when it does not, the line says `build: not exposed` and the doctor checks the other two. When the harness hosts its own instance, the doctor checks what the harness needs instead (its build, the services it depends on), and a failed harness drive is judged by the harness's own output plus this doctor. A run executes it before its first drive and again after any failed drive. |
| Isolation | Whether two instances can run at once (ports, data directories, browser profiles), and what to do when they cannot. |
| Written at | The commit the map was written or last refreshed at. |
| Features | One line per feature file: its title, its file name, and how many entry points it lists. |

A minimal index body for a time-tracking web app:

```markdown
- Application: Clockwork web, built from `apps/web`
- Launch: `run-clockwork` (project skill)
- Driver: playwright, from docs/conventions/testing.yaml
- Doctor: `curl -fsS http://127.0.0.1:5180/healthz` prints `{"status":"ok","build":"<sha>"}`
- Isolation: one instance per port; set `CLOCKWORK_DB` to a scratch file per run
- Written at: 3f9c2a1

## Features

- Start a timer: `start-a-timer.md` (3 entry points)
- Weekly timesheet export: `weekly-timesheet-export.md` (2 entry points)
```

This app reports its build in the health response, so the doctor checks it. For an app that shows
no build identifier, the doctor line names the other two checks and ends `build: not exposed`:

```markdown
- Doctor: `curl -fsS http://127.0.0.1:5180/healthz` answers and lists the project `Website refresh`; build: not exposed
```

## Feature files

Each feature file opens with an H1 naming the feature and one sentence on what the user gets from
it. Four H2 sections follow, always in this order:

1. `## Parts`: the distinct behaviours inside the feature, one short line each, so a change can be
   matched to the part it touches.
2. `## Entry points`: every way a user reaches the feature (a button, a keyboard shortcut, a route,
   a command, an API call), one line each. A run drives each one the change can affect; a proof
   through one entry point says nothing about the others.
3. `## Drive`: how to exercise the feature with the recorded driver. State the starting data, then
   match every user action to the exact handle (an accessible name, a route, a command line) and
   the result a run must observe, including a second read of anything the feature stores or sends.
4. `## Traps`: what has made a run lie or fail before: timing, seeded data a run must reset, a
   dry-run mode that still touches the network, a cache that hides a stale page.

Write it from the user's side: no class names, no internal endpoints, no test-only hooks. The map
names what a user does and what a user sees. Under the `harness` driver, `## Drive` may add one
line with the harness command that drives the feature, for example the test filter that selects
it; the steps above it stay written from the user's side.

A feature file for the time-tracking app:

```markdown
# Start a timer

A user starts tracking time against a project and sees the elapsed time grow.

## Parts

- start: a new timer begins at 00:00 for the chosen project
- switch: starting a second timer stops the first and saves its entry
- resume: a timer survives a page reload

## Entry points

- the `Start` button on the dashboard
- pressing `t` anywhere on the dashboard
- `POST /api/timers` from the browser extension

## Drive

Start from an empty scratch database with the project `Website refresh`.

- Choose `Start` in the row named `Website refresh`; the row shows a running clock within two seconds.
- Reload the page; the same clock is still running and has not reset.
- Read the entry back through `GET /api/entries?project=website-refresh`; it lists one open entry.

## Traps

- The clock renders from the browser's time zone; compare durations, not wall-clock strings.
- A timer left running from an earlier run makes `start` look like `switch`; reset the database first.
```

## File names

A feature file's name is its title through one slug rule, plus `.md`:

1. Lower-case the title.
2. Replace each run of characters outside `a-z0-9` with a single `-`.
3. Drop any `-` at the start or end; an empty result becomes `run`.
4. Cut the result to 64 characters.

`Billing / Export!` becomes `billing-export.md`; `Start a timer` becomes `start-a-timer.md`. The
same rule names run-e2e's browser sessions. When two titles give the same slug, the second gets
`-2` and the third `-3`: cut the slug to 64 characters minus the suffix's length, drop a trailing
`-`, then append the suffix. The name before `.md` always matches `^[a-z0-9-]{1,64}$`.

## Which driver drives

A session instruction wins. Then the driver the map records for that app. Then the resolved
`e2e_driver`. The map keeps the driver it was written with, so changing `e2e_driver` later changes
nothing until the map is rewritten or its index edited. A map whose driver is `chrome` drives only
attended runs: an unattended run stops with the gap report instead of switching drivers.

## How run-e2e uses the map

When a map exists at the resolved `feature_map_dir`, `/testing:run-e2e`:

1. runs the index's doctor before the first drive, and again after any failed drive before it calls
   the failure a product failure;
2. maps each changed file to the features whose parts it touches;
3. drives every entry point those features list;
4. reports one line per entry point: driven and passed, driven and failed, or not driven with the
   reason.

`/verification:confirm` holds its verdict below `CONFIRMED` while any listed entry point for a
changed feature is missing from that report.
