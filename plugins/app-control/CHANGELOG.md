# Changelog

All notable changes to the `app-control` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.0] - 2026-10-25

### Added

- `/app-control:map refresh` keeps a control skill in line with the app and ends `clean`, `changed` or `blocked`. It skips when nothing changed since the last clean pass on this host, refuses an attended-only control skill when unattended, runs a read-only source wave of one subagent per feature in waves filled to six before the next starts, then drives every feature through `/app-control:drive` with Ready before the first drive and after any failed one, cleanup after each drive and every evidence path checked after cleanup. Each difference is triaged as doc drift (corrected), driver gap (on an attended pass fixed in `cli/` and shipped only after a live re-drive; on an unattended one reported unwritten; never by loosening a floor) or product regression (left as written and reported, or sent to `/bugs:write`, never put in the pull request). Edits stay inside the control skill's directory and go out on `control-skill-upkeep/control-<slug>` (the control skill's directory name), from the default branch, merged into and never rebased, through at most one pull request; every local and remote `feature-map-upkeep/*` branch is reported by name, not adopted. A pass over several control skills uses one branch per skill and returns to its starting branch between them. A legacy testing feature map at the path the person passes, or a control skill's flat feature files, is converted to the contract's folder layout in the same upkeep pull request, with the old files moved in that commit. A legacy map is converted first, uncommitted on the upkeep branch and after an attended pass approves the planned conversion, so both passes drive the converted control skill; a tracked legacy map with uncommitted changes blocks the conversion, and a pass that stops before the commit deletes what the conversion created, restores the legacy files from a copy taken outside the checkout before the first write, and returns to its starting branch. Reauthored from the upkeep loop, its three live-pass invariants and its triage of pstack's `maintain-verification-skill` ([cursor/plugins](https://github.com/cursor/plugins), MIT).

## [0.7.0] - 2026-10-25

### Added

- `/app-control:map check` reports where a control skill breaks the contract and edits nothing. A bundled script prints one `<rule> | <path> | <detail>` line per structural finding: an index line that names no feature file, is dead, duplicated or missing, or miscounts its entry points, a source glob that matches no file or leaves the project root, a feature README whose sections are missing, extra or out of order, an entry point with no `driven` marker or a `not driven` with no reason, a relative link that resolves to nothing, and a `shared/` item used by fewer than two features or lacking its `Why shared:` line. The model then reports any section that copies a recipe instead of naming it. The report carries no verdict word.
- The control-skill contract gains a "Shared items" section: `shared/` holds only what two or more features use, each item a direct child of `shared/` that a feature uses by naming `shared/<item>`, with a `Why shared: <reason>` line in its `README.md` or in the file itself.

## [0.6.0] - 2026-10-24

### Added

- `/app-control:map create` generates a project's control skill: it walks fixed discovery rows over the repository before asking anything, asks only what discovery left open (through `/planning:interview` when installed), writes the hub, feature folders, config, driver CLI and one pointer in the repository's source instruction file, then proves it once through `/app-control:drive` and checks the evidence survived and no process it started is alive. The control skill is written only to `.claude/skills/control-<slug>/`, where drive finds it, with every path's real location checked inside the repository. `--unattended` is a dry run that writes nothing and never guesses a safety answer. Reauthored from the create-and-prove flow of pstack's `create-verification-skill` ([cursor/plugins](https://github.com/cursor/plugins), MIT).
- The control-skill contract gains three sections: writing the driver CLI (through `/developer-experience:build-cli` when installed, else a documented script), config layered from committed `config/defaults.json` through `config/local.json`, environment variables and flags with each value's layer reported, and safety floors that ship safe (an empty recipient allowlist, one sign-in attempt per account per run, read-only production, no unattended writes), loosen only in config committed at HEAD, and are enforced by the generated driver CLI (all but the per-run sign-in count, which the caller keeps), which refuses a loosening from any other layer with exit 4. Credentials always come from environment variables and are reported by variable name and set or unset, never by value.

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
