# Evidence layout

## Contents

- Run directory
- report.md
- report.json
- report.public.md and report.public.json
- Mask post-check
- affected.json

## Run directory

One directory per run: `--out <dir>` when given, else a new temporary directory whose path the
report prints. It holds `report.md`, `report.json` and the artifacts. Each artifact name carries the
feature and entry point it came from, and the tier for a capture with a row per tier, for example
`checkout-cart-02-screenshot.png`, or `checkout-cart-02-server-cpu.cpuprofile` for a tier row. A
`screenshot` or `video` has its sidecar beside it, `checkout-cart-02-screenshot.png.txt`, written
by the Capture command (control-skill contract, "Writing the Capture section").

Raw captures (traces, profiles, heap snapshots, thread dumps, profiler recordings) are written straight into this
directory and kept as evidence. Drive's `cleanup` never deletes the run directory or anything in it:
it checks that each capture exists and is not empty, and deletes only the scripts this run wrote and
the temporary directories that hold them. The run directory stays until the caller or the person
deletes it. A heap snapshot or trace can hold whatever the process held in memory, secrets
included, so the report marks each raw capture "may hold secrets; do not commit", and says so when
the run directory sits in a git working tree and is not ignored. A command line can carry a token
as an argument, so `report.md` and `report.json` carry the same mark once they hold one.
`report.json` records each mark in `secrets_mark`.

## report.md

For a person. It lists, in order: the mode and the control skill (or the line
`No control skill: drive used <fallback>.`), the launch record, what `ready` found and its exit status, each step with its action, entry
point, observed text and artifact paths (a capture step also names the process, by pid, name,
start time and command line, and the exact command run), then capability gaps, `blocked:` lines and cleanup. It
records what was done and seen. It rates nothing and says nothing about whether a change works.

## report.json

For a job. One object with these fields:

| Field | Holds |
|---|---|
| `app` | The app's name |
| `control_skill` | The control skill used, by full name and source, such as `control-shop (project: .claude/skills/control-shop/SKILL.md)`, or `harness-ops:control-claude-code (plugin: <folder>/skills/control-claude-code/SKILL.md)`, or `null` |
| `fallback` | What drive used when `control_skill` is `null`, else `null` |
| `mode` | `interactive` or `unattended` |
| `trusted_root` | The real path of `--trusted-root <dir>` when the run had it, else `null` |
| `launch` | A list with one entry per process this run launched, one per app: `app`, `pid`, `uid`, `start_time` (the integer the process table gives, compared exactly), `command_line` (a display form) and `command_line_sha256` (over the raw command line bytes, on Linux every byte of `/proc/<pid>/cmdline` as read, trailing NUL included); an empty list when the run launched nothing. A record written as one object, as earlier runs wrote it, reads as a list of one |
| `ready` | `environment` (the selected name, or `null`), `surfaces` (URL, port or command), `services` (each dependency service's name, url, whether it answered, and whether the app's exposed target matches it, or `not exposed`), `build`, `data`, `telemetry`, `exit` (the Ready command's exit status, or `null` when it did not run) |
| `steps` | A list; each has `action`, `entry_point`, `observed` (text) and `artifacts` (paths); a step from a steps file also has `id` and `outcome` (`done`, `failed`, `skipped: optional` or `blocked: <reason>`) and `finally: true` for a finally step, and a step a failure ended is not listed; a capture step also has `process` (pid, name, start time and command line, plus the uid and command line sha256 when a pid-bound capture or an elevated attach bound it, and the parent pid when a wrapper resolved to it) and `command` (the exact command run) |
| `secrets_mark` | A list with one entry per raw capture, plus `report.md` and `report.json` once they hold a command line: `path`, `mark` (`may hold secrets; do not commit`) and `unignored_in_git_tree` (`true` when the run directory sits in a git working tree and is not ignored); an empty list when the run wrote no raw capture and recorded no command line |
| `capture_count` | The number of captures the run wrote, of every kind, sidecars not counted |
| `artifacts` | One entry per capture: `path`, `kind`, `mask` (`applied`, `none-declared`, `not-checked` or `hit`, per [Mask post-check](#mask-post-check)) and `publishable` (`true` or `false`) |
| `publishable` | The paths safe to upload: each capture whose `publishable` is `true`, then `report.public.md` and `report.public.json` when the post-check passed them; an empty list when none passed |
| `capability_gaps` | Signals and capture kinds the app or project does not provide |
| `blocked` | Each step that needed a person or a grant, with its reason and the narrowest grant |
| `cleanup` | What was stopped, and each evidence path with whether it exists and is not empty |

The file has no field that rates the outcome. The caller decides what the evidence means.

## report.public.md and report.public.json

Copies of `report.md` and `report.json` for upload, written by every run that writes a report.
Each command line (`launch[].command_line`, `steps[].command`, `steps[].process.command_line`, a
command in `ready.surfaces`) and each `observed` text reads `[redacted]`. `report.public.json` leaves out `secrets_mark` and
`publishable`. They go in `publishable` only when the post-check passes them, like a capture.

## Mask post-check

Run after the last capture: scan the sidecars and set each capture's `mask`, then write the two
public reports and scan them, then give `report.json` its `publishable` list. Each later rewrite
of the report, cleanup's included, rewrites the public reports and scans them again. It decides what may
leave the machine; the run directory stays whole for the caller to read locally. It fails closed:
whatever it cannot show clean is not publishable.

1. **Values.** Resolve each source on the hub's `## Mask` `values:` line: a config field through
   the Config layers, a `cli/` command run read-only, its stdout one value per line. Hold the
   values in memory and never write one to any file, the report included. A source that fails or
   yields no value leaves every capture `not-checked` and both public reports unpublished.
2. **Scan.** Scan each `screenshot` and `video` sidecar, `report.public.md` and
   `report.public.json`. First delete box-drawing characters (U+2500 to U+257F), then join line
   wraps by deleting each line break with the whitespace around it. A hit is either:
   - a value found in the text, ignoring case, whitespace and `|` in both, so a value wrapped
     across two rows or split by a table border still matches;
   - the generic credential pattern, ignoring case: an email address; `Bearer`, a space, then 8 or
     more characters with no whitespace; a key whose name holds `token`, `secret`, `password`,
     `apikey` or `api_key`, then an optional quote, `=` or `:` and an optional quote, then a value
     of 8 or more characters, none of them whitespace, `*` or `•`; or a PEM private key header
     (`-----BEGIN`, then `PRIVATE KEY-----`).
3. **Mask state.** Each capture's `mask`:
   - `hit`: the scan of its sidecar found a hit;
   - `applied`: the hub's `## Mask` has mask lines, the sidecar is not empty and was modified after
     this capture's command started (one left by an earlier run in the directory does not count),
     and the scan found nothing;
   - `none-declared`: the same, with `## Mask` reading `none: <reason>`;
   - `not-checked`: anything else, such as a run with no control skill, a hub with no `## Mask`
     line, a missing, empty or older sidecar, a `values:` source that did not resolve, or a kind
     other than `screenshot` and `video`.
4. **Publishable.** A capture is publishable only when it is a `screenshot` or `video`, its `mask`
   is `applied` or `none-declared`, and it has no `secrets_mark` entry. For a video, its sidecar
   holds every frame's text, so it passes only when every frame does. A public report is
   publishable when its scan found nothing and every `values:` source resolved. A raw capture, a
   sidecar, `report.md`, `report.json` and any file with a `secrets_mark` entry are never
   publishable.

With no control skill there are no values: the public reports are scanned for the generic pattern
alone, and every capture is `not-checked`.

## affected.json

Written by `affected` into the run directory, by `scripts/affected_features.py`. One object:

| Field | Holds |
|---|---|
| `app` | The app's name |
| `control_skill` | As in `report.json`, or `null` |
| `source` | `project`, `plugin` or `none` |
| `trusted_root` | As in `report.json` |
| `base`, `head` | The refs the diff `<base>...<head>` was taken between |
| `features` | One entry per feature a changed file maps to, in index order: `id` (as `features/<id>/README.md`), `title` (the index line's), `entry_points` (each `text`, `driven`, and `reason` for a `not driven: <reason>` line, else `null`) and `matched_files` |
| `unmatched_files` | Each changed file no feature's `sources` matched |
| `note` | `No control skill: nothing matched`, `control skill present, <n> files unmatched` when no feature matched, each index path that is not a feature file inside the control skill or could not be read, joined by semicolons, or `null` |

The changed files are the old and new path of each change, a rename included, relative to the
repository root. A file maps to features as the control-skill contract's "Hub" says, a matched
module line through its `## Sub-features` lines. A `sources` glob resolves against the project
directory for a project control skill and against the repository root for a plugin one: `**`
matches across `/`, `*` and `?` match within one path segment, and every other character matches
itself.
