# Changelog

All notable changes to the `app-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
