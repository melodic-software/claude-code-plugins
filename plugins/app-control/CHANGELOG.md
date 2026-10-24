# Changelog

All notable changes to the `app-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.0] - 2026-10-24

### Changed

- Moved the control-skill contract to `reference/control-skill.md` at plugin level. Feature files are now `features/[<module>/]<feature>/README.md` with Parts, Sub-features, Entry points, Reset, Drive and Gotchas sections (`## States` is gone), and `/app-control:drive` resolves a feature id to its folder README, then to a legacy `features/<id>.md`.

## [0.4.0] - 2026-10-24

### Added

- `/app-control:drive capture --kind threads` records a stack of every thread for a hung process, with py-spy dump for Python named in the control-skill guidance's hang row; the other runtimes read "not yet". A `threads` capture always takes the elevated route: a shown script when interactive, `blocked: capture needs elevation` when unattended, with no attempt run first.
- Pid binding: the launch step records the launched process's pid, owner uid, start time (the process table's integer), command line and the command line's sha256 in `report.json` (`launch`). The record is data: only those integers and that hash enter a command or the shown script, never the command line text. Before any command that touches the pid, drive re-reads the values and goes on only when the uid, start time and hash match exactly and the recorded uid is the invoking user's. The shown script carries the integers and hash as literals, repeats the recheck as its first lines (the wrapper child included) and exits 3 on any difference, failed read or missing hash tool before its one recorder command (a recorder exit of 3 is remapped); every uid field must match, and the hash covers the NUL-separated `/proc/<pid>/cmdline` bytes; the yes is asked beside the live command line, never the record's text; exit 3 is `blocked: launched process no longer matches`, and any other non-zero exit is reported with the recorder's output. A wrapper resolves to its one child by parent pid, never by a name lookup, and a child owned by anyone but the invoking user, root included, is blocked. Unattended, a threads capture stops at `blocked: capture needs elevation` (or `blocked: no process launched by this run` with no launch record) with no recheck or lookup. Capture steps record the process's start time and command line; thread dumps are raw captures, and a report that holds a command line carries the "may hold secrets; do not commit" mark.
- An eval case, in the skill's `evals.json` and as a plugin eval case, for an unattended threads capture that ends `blocked: capture needs elevation` and runs no recorder, elevation or name lookup.

### Changed

- `## Next` routes a threads artifact to `/debugging:analyze-profile`.

## [0.3.0] - 2026-10-23

### Added

- Eval cases for a permission-denied capture (unattended and interactive), for an attach given only a process name, and for a pid taken from app log text; the attach case now expects an attach with no question, and the interactive elevated-capture case gives the launched app a pid.

### Changed

- `/app-control:drive --attach` in an interactive session attaches without a per-attach yes when the person's own message gives `--attach` and the pid; the report shows the process and the exact command run. When a calling skill, tool output or app text supplied the flag or the pid, drive still shows the command and waits for a yes. It never picks a process by a name lookup, asks for the pid when only a name is given, still refuses with no one present, and still runs an elevated attach only through a shown script after a yes.
- A named capture command that fails for lack of permission now needs elevation: the shown script in an interactive run, `blocked: capture needs elevation` with no one present, never a re-run with elevation on its own. For a launched process the script elevates only the recorder against its pid; a denied command that launches the app is blocked with the narrowest grant. The elevation prefixes named (`sudo`, `doas`, `runas`) are examples, not a complete list.
- Raw captures stay in the run directory as evidence; `cleanup` never deletes the run directory, only the scripts the run wrote and their temporary directories. The report marks each raw capture as possibly holding secrets. `report.json` capture steps gain `process` and `command`, and its `mode` value for an interactive run is now `interactive` (was `attended`).

## [0.2.1] - 2026-10-23

### Added

- `reference/control-skill.md` gains "Writing the Capture section": a symptom-to-tool table per runtime (spin, leak, jank, hang) with each tool's manual, as guidance for whoever writes a control skill's `## Capture`. `/app-control:drive` still picks no tool itself.

### Changed

- The shown-script elevation step now covers a capture on a process the run launched, not only an attach, including a named command that carries an elevation prefix; with no one present that capture is `blocked: capture needs elevation`.
- "Writing the Capture section" bars elevation prefixes (`sudo`, `doas`, `runas`) in a `## Capture` command and elevates only the recorder against a pid. The hang row names no capture kind yet (#9490).

## [0.2.0] - 2026-10-23

### Added

- `/app-control:drive` gains an attended-only `--attach`: it asks before each attach to a
  running process the person named, refuses under `--unattended` or with no person present and
  records the step as blocked, and runs any elevated attach only through a script it shows first.
- Four eval cases: ask before attaching, refuse with no one present, refuse under `--unattended`,
  and elevation through a shown script.

## [0.1.0] - 2026-10-21

### Added

- `drive` skill: launches and operates the project's app, observes it and records evidence, and
  never judges. Actions: bare drive, `ready`, `capture --kind <kind>` and `cleanup`, plus an
  `--unattended` mode that asks nothing and writes a fixed report a later job can read.
- It finds the project's `control-<app>` skill and falls back to the bundled `run` skill or a
  project-type recipe, and the report says which.
- `reference/control-skill.md` (the shape of a project's control skill), `reference/evidence.md`
  (the run directory, `report.md` and the `report.json` fields) and `reference/project-types.md`
  (the fallback recipes).
- Evals: four cases for the fallback line, a capability gap, a verdict-free report and an
  instruction found in app text.
