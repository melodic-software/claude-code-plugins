# Evidence layout

## Contents

- Run directory
- report.md
- report.json

## Run directory

One directory per run: `--out <dir>` when given, else a new temporary directory whose path the
report prints. It holds `report.md`, `report.json` and the artifacts. Each artifact name carries the
feature and entry point it came from, for example `checkout-cart-02-screenshot.png`.

Raw captures (traces, profiles, heap snapshots, thread dumps, recordings) are written straight into this
directory and kept as evidence. Drive's `cleanup` never deletes the run directory or anything in it:
it checks that each capture exists and is not empty, and deletes only the scripts this run wrote and
the temporary directories that hold them. The run directory stays until the caller or the person
deletes it. A heap snapshot or trace can hold whatever the process held in memory, secrets
included, so the report marks each raw capture "may hold secrets; do not commit", and says so when
the run directory sits in a git working tree and is not ignored. A command line can carry a token
as an argument, so `report.md` and `report.json` carry the same mark once they hold one.

## report.md

For a person. It lists, in order: the mode and the control skill (or the line
`No control skill: drive used <fallback>.`), the launch record, what `ready` found, each step with its action, entry
point, observed text and artifact paths (a capture step also names the process, by pid, name,
start time and command line, and the exact command run), then capability gaps, `blocked:` lines and cleanup. It
records what was done and seen. It rates nothing and says nothing about whether a change works.

## report.json

For a job. One object with these fields:

| Field | Holds |
|---|---|
| `app` | The app's name |
| `control_skill` | The control skill used, or `null` |
| `fallback` | What drive used when `control_skill` is `null`, else `null` |
| `mode` | `interactive` or `unattended` |
| `launch` | The process this run launched: `pid`, `uid`, `start_time` (the integer the process table gives, compared exactly), `command_line` (a display form) and `command_line_sha256` (over the raw command line bytes, on Linux the NUL-separated `/proc/<pid>/cmdline`), or `null` when the run launched nothing |
| `ready` | `surfaces` (URL, port or command), `build`, `data`, `telemetry` |
| `steps` | A list; each has `action`, `entry_point`, `observed` (text) and `artifacts` (paths); a capture step also has `process` (pid, name, start time and command line, plus the parent pid, uid and command line sha256 when a wrapper resolved to it) and `command` (the exact command run) |
| `capability_gaps` | Signals and capture kinds the app or project does not provide |
| `blocked` | Each step that needed a person or a grant, with its reason and the narrowest grant |
| `cleanup` | What was stopped, and each evidence path with whether it exists and is not empty |

The file has no field that rates the outcome. The caller decides what the evidence means.
