# Changelog

All notable changes to the `explainer-video` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [2.1.1] - 2026-11-14

### Changed

- The verification level reader now reads the team file through `lib/default-branch-file.sh`; levels and messages are unchanged.
- `lib/default-branch-file.sh` reads the last fetched copy of the default branch when the fetch fails, and says it may be stale, instead of exiting 2; the stills settings still never come from the working tree.

### Fixed

- `/explainer-video:produce`'s Related section names only what each related skill does today; it no longer describes
  `/education:illustrate` or the reviewer-media skill as callers of the stills renderer.

## [2.1.0] - 2026-11-14

### Added

- A stills renderer: `/explainer-video:produce` turns a `storyboard.json` into one narrated video of held
  3840x2160 frames with burned captions, chapters, a contact sheet and a `manifest.json`, checked against a luma
  SSIM floor of 0.999 per frame and scanned for secrets and machine data before anything renders. New settings:
  `stitcher` and `frame_stylesheet` (read from the default branch only), `upload_limit_mb`. Playwright for Python joins the requirements;
  its Chromium downloads on the first stills render.
- A shared media library (`media_*.py`, `media_templates/`) vendored from `lib/media-render`: frame capture through
  Playwright for Python, frame templates, storyboard timeline, captions, encode profiles, loudness, verification,
  upload-size splitting, contact sheets and a secret and machine-data scan.

### Changed

- `render.py` muxes, normalizes loudness and builds captions through the shared library; output is unchanged.

## [2.0.1] - 2026-11-14

### Fixed

- The shared hook library's command reader now says, when shfmt rejects text a guard lifted out of the command and named with `HOOK_BPS_SPAN`, which guard refused, that shfmt's `line:col` counts from the start of that text rather than the command, and the text's first 60 characters. Its own second readings (a backtick's unescaped text, a joined here-doc body) name themselves the same way. A refusal of the command itself reads as before.

## [2.0.0] - 2026-11-13

### Changed

- **Breaking:** the `verification` level now defaults to `light` when the default branch sets no `verification` key or cannot be read: verifier dispatches are skipped and the skip line is written. An invalid value or a team file that does not parse still resolves `standard`, naming the error. Set `verification: standard` (or `strict`), or `verification_skills.<skill>`, in the team file on the default branch to raise it.

## [1.1.13] - 2026-11-13

### Security

- The locked Python set pins `soupsieve` 4.0, up from 2.10, which fixes a polynomial-time denial of service in the descendant combinator (GHSA-mmhr-3c5m-f64f).

## [1.1.12] - 2026-11-13

### Changed

- The vendored prerequisites checker's usage and schema errors give `EXAMPLE_ENABLED` as the sample option name, one that names no plugin.

## [1.1.11] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [1.1.10] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [1.1.9] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [1.1.8] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [1.1.7] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [1.1.6] - 2026-11-11

### Changed

- `produce`'s caption-timing pointer links the BBC guidelines' section 4.1 anchor.

No behavior change.

## [1.1.5] - 2026-11-09

### Changed

- Internal simplification, no behavior change.

## [1.1.4] - 2026-11-09

### Changed

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

- Simplified the internals of the hook launcher; its behavior is unchanged.

## [1.1.3] - 2026-11-09

### Changed

- Simplified the shared resolve-convention-home.sh, resolve-convention-pattern.sh and rewrite-guard.sh copies; behavior is unchanged.

- **Shared `hook-utils.sh` synced; no change to this plugin's hooks.** The builtin JSON field readers share one key-depth check, and three helpers drop redundant steps.

## [1.1.2] - 2026-11-09

### Changed

- Shared `hook-utils.sh` synced where this plugin carries it (#14227): `HOOK_TELEMETRY_SINK=@harness-ops` sends this plugin's hook telemetry to the harness-ops reference sink, and any other value starting with `@` is reserved and skipped. No other change to this plugin.

## [1.1.1] - 2026-11-06

### Changed

- The shared `exec-bash.mjs` launcher has a `--bps-seed <hook-utils.sh>` flag. On Windows it parses a Bash or PowerShell call's command once with shfmt and jq and hands the result to the script, so Git Bash does not fork the processes of that parse. The flag is inert on other platforms, and an inherited result is always dropped (#6634).

## [1.1.0] - 2026-11-06

### Added

- A `verification` level (`off`, `light`, `standard`, `strict`) and per-skill `verification_skills` in `<home>/explainer-video.yaml`, read from the default branch by `lib/read-verification.sh` and validated by `schemas/explainer-video.schema.json`. Under `light` and `off`, `/explainer-video:produce` dispatches no frame judge, records `verification: skipped (<level>)` and reports the frames as not independently judged; `render.py`'s checks still run.

### Changed

- `/explainer-video:produce` no longer calls a video done on its own read of the frames: step 7 dispatches a fresh-context subagent that judges the delivery frames against the narration script (the beat plan when silent), and a defect it returns sends the scene back to step 4. Your own frame reads stay as the fix loop.

## [1.0.4] - 2026-11-06

### Changed

- Shared `hook-utils.sh` synced where this plugin carries it: an opt-in shfmt parse memo that only the guardrails Bash dispatcher turns on (#6634); no change to this plugin's behavior.

## [1.0.3] - 2026-11-04

### Changed

- The produce skill's eval suite moved from `skills/produce/evals/evals.json` to `evals/<case>/case.yaml` and `prompt.md`: six legacy cases became eight `pr-*` cases that grade the run's decisions without needing a render to succeed, and the missing-tool case is covered by `ck-notice-runs-own-report` ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). `evals.json` is deleted.

## [1.0.2] - 2026-11-04

### Changed

- The shared `hook-utils.sh` reads Bash commands from `shfmt --to-json` (`hook::bash_parse_segments`
  keeps its callback and `HOOK_SEG_*` contract), and the hand-written segmenter is removed. It
  refuses the call when shfmt or jq is missing, fails, runs past 5 seconds, or rejects the text
  (an unclosed here-doc, for one, which bash runs with a warning), and the refusal names which of
  those happened, quoting shfmt's syntax error. It uses a shfmt in `~/.local/bin` when PATH has
  none. The 5-second bound is the `read -t` builtin, so a parse forks the same processes on every
  run and needs no `sleep` or `timeout` command.

## [1.0.1] - 2026-11-04

### Fixed

- The `SessionStart` row no longer fails on every new session when `node` is not on `PATH`: it runs through `lib/node-or-skip.sh` and exits 0 silently, and harness-ops' node notice tells the user.

## [1.0.0] - 2026-11-03

### Removed

- The `check` skill is gone. To check this plugin's prerequisites, run `python3 "<plugin root>/scripts/pydeps.py" check --data-dir "<plugin data>"`.

## [0.4.9] - 2026-11-02

### Changed

- Hook notices name the bundled checker command; `check` is optional (#12485).

### Fixed

- The shared hook library's Bash segment parser (`hook::bash_parse_segments`) now passes each substitution in an unquoted here-doc body (`$(...)`, a backtick pair, `${...}`, `$[...]`) to its callback as segments of their own, because bash runs them. A body under a quoted delimiter is still skipped as data.

## [0.4.8] - 2026-11-02

### Changed

- The `SessionStart` hook `install-python-deps.sh` starts no process while its ready stamp holds: after a successful install with an interpreter found on PATH, `pydeps.py` writes `<data>/python/.hook-ready`, and the hook skips the interpreter probe, `cygpath` and the ManimCE load probe until the plugin root, a candidate interpreter's resolution, that interpreter's file, `requirements.txt`, `pydeps.py` or `pydeps.json` changes, or the installed set is gone. `pydeps.py run` drops the stamp when the set is missing or a script exits non-zero, and `check` when a row fails, so the next session start probes and rebuilds ([#12258](https://github.com/melodic-software/claude-code-plugins/issues/12258)).

### Fixed

- The shared `hook-utils.sh` Bash command parser keeps a `#` right after the closing `)` of an
  array assignment, an extglob, `$(…)`, `$((…))`, `<(…)` or `>(…)`, or after a closing backtick,
  in its word, as Bash does, instead of reading it as a comment that hid the rest of the line.
  Those frames now stay open across `;`, `|`, `&` and newlines inside them, a `case` pattern's
  `)` no longer closes one, and `case` or `esac` inside arithmetic is read as a variable name.
- A comment, a quote of any kind, a here-doc delimiter or a here-doc body inside backticks now
  ends at the closing backtick, as in Bash; an escaped backtick does not close it, and outside a
  comment or quote it opens or closes a nested substitution whose commands are read.
- Case statements follow Bash's pattern-position rules: a pattern spelled `case` opens nothing,
  `esac` after `|` is a pattern, `case x in esac` closes on one line, and `\;;` is a word and a
  `;`, not a clause end, and a pattern word that starts with `$(…)`, a backtick or `@(…)` is
  the first pattern word. Inside an extglob or arithmetic a `#`, `<` or `>` is literal text.
- `((…) )` and `$((…) )`, which Bash re-reads as nested subshells, are read as commands with
  real redirections, not as arithmetic. The parentheses of a `[[ … =~ … ]]` regex are regex
  text, not an array assignment.
- A here-doc takes its body only at a newline on the level where it was read, so one read
  before a `$(…)`, backtick, `a=(…)` or `@(…)` that spans lines takes its body after the line
  where that construct closes; a syntax error inside `a=(…)` cancels the line's here-docs.
- For `!(x)#` and `f@()#`, where the `#` is literal with `shopt -s extglob` and a comment
  without it, the parser now reports the commands of both readings, and `HOOK_HEREDOC_BODIES`
  lists each here-doc body once, in source order.

## [0.4.7] - 2026-11-02

### Changed

- The `SessionStart` node-notice row is gone (#6633): harness-ops' row reports a missing `node` for the whole fleet, once per session. Without harness-ops, no session-start notice says `node` is missing.
- Shared `prerequisites.mjs` synced where this plugin carries it (#6633): a manifest may declare an optional `session_probe`, which opts the plugin into harness-ops' session-start probe.

## [0.4.6] - 2026-11-01

### Added

- Frozen trigger-probe sets for the two model-invoked skills (`produce` with 19 probes, `check` with 18), for measuring description auto-invocation in a later round.

## [0.4.5] - 2026-10-30

### Changed

- Shared `exec-bash.mjs` synced: `--skip-unless-marker` also skips when every `<session>.launched` it finds holds a launch token that `<session>.seen` beside it repeats. No hook in this plugin uses that flag; no other change to this plugin.

## [0.4.4] - 2026-10-30

### Changed

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

- Shared copies synced: links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.4.3] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.4.2] - 2026-10-27

### Security

- The `--skip-unless-marker` hook launcher no longer skips a monitor because of a launch-marker directory in the shared temp folder that another local user created, or a symlink in its place: off Windows that directory counts only when it is a real directory owned by the current user, as the disk-hygiene hook script already required.

## [0.4.1] - 2026-10-27

### Security

- Shared `prerequisites.mjs` synced: each dependency probe runs from the library's own directory, so a probed tool never starts with the user's repository as its working directory.

## [0.4.0] - 2026-10-27

### Added

- The vendored `hooks/exec-bash.mjs` launcher takes `--require-verdict`, a per-row opt-in for a blocking hook row: it names a marker file in the script's `EXEC_BASH_VERDICT_FILE`, and a script that exits 0 without writing it is denied (exit 2, one stderr line), because Windows Git Bash reports a crashed bash as exit 0 with empty output. This plugin's rows do not pass the flag, so they behave as before.

## [0.3.5] - 2026-10-26

### Changed

- hook-utils: `hook::bash_parse_segments` leaves the byte span of each here-doc body it skips in `HOOK_HEREDOC_BODIES`, along with whether its delimiter was quoted, so a guard can tell a quoted body's text from the commands around it (#8949). A here-doc delimiter word now ends at `(` or `)`, as it does in bash.

## [0.3.4] - 2026-10-25

### Fixed

- `prerequisites.json` caps the `python` entry with `below: "3.14"`, so a host whose only Python is 3.14 is reported outdated instead of ready. The install hook runs only on Python 3.12 or 3.13.

## [0.3.3] - 2026-10-25

### Changed

- Shared `prerequisites.mjs` synced where this plugin carries it (#9684): `detect.version` accepts an exclusive `below` bound; no other change to this plugin.

## [0.3.2] - 2026-10-22

### Changed

- Synced the shared `exec-bash.mjs` launcher, which gains an opt-in `--fail-closed` flag. This plugin's hooks do not pass it, so their behavior is unchanged.

### Fixed

- Upgrade Pillow to 13.0.0 for GHSA-8g5g-8vmr-9782.

## [0.3.1] - 2026-10-20

### Changed

- The vendored `hook-utils.sh` comments no longer name the retired `block-hook-bypass` guard. Comment-only change; no runtime behavior changes.

### Removed

- The hook launcher no longer accepts the unused `--skip-if-all-false` flag.

### Fixed

- Shared `prerequisites.mjs` synced: a `node-pkg` or `python-pkg` entry reads `CLAUDE_PLUGIN_DATA` only when its last path segment is this plugin's name or starts with `<plugin>-`, and treats a literal `${...}` value as unset, so another plugin's data directory reports `unverified` instead of `missing`.

## [0.3.0] - 2026-10-18

### Changed

- **`/explainer-video:produce` normalizes narrated loudness.** `render.py` runs ffmpeg `loudnorm` in two passes on the narration before the mux, measures the muxed file again, and fails it when its integrated loudness is off the target or its true peak is over the ceiling (`loudness` in the new `scripts/defaults.json`). `report.json` records the source and delivered measurements and whether linear or dynamic normalization ran.
- **Captions are timed to be read.** Each sentence splits into the fewest balanced cues, so no cue is a one-word tail; a cue too short to stand joins its neighbor; each cue stays up for the minimum and the reading time per word where the next cue allows. A cue still under the minimum fails the render; one read faster than the per-word time is a `FLAG:` line (`captions` in `scripts/defaults.json`).
- **Still spans are reported.** Every render lists each span with no change in picture (ffmpeg `freezedetect`) and, when narrated, the words spoken during it, as `STILL:` lines and `stills` in `report.json`. They never fail a render.
- The skill states the read-back frame cap and the summary line says how many animation ends the frame list covers.

## [0.2.14] - 2026-10-16

### Fixed

- The empty-output-folder render test now asserts the folder is still empty after `clear_previous`, so it fails if the cleanup creates files.

## [0.2.13] - 2026-10-16

### Changed

- Shared `prerequisites.mjs` synced: the SessionStart probe now also reports a drifted git-hook entry for a plugin that ships `git-hooks/entries.json`. This plugin ships none, so its behavior is unchanged.

## [0.2.12] - 2026-10-13

### Changed

- **Shared `prerequisites.mjs` synced: its per-probe timeout is now 20 seconds, up from 5.** A version or `system-lib` probe that resolves a secret or calls a network API, such as `firecrawl --status` behind a key-injecting wrapper, no longer false-fails on a slow run. A fast probe is unaffected; a hung one now costs at most 20 seconds per entry. No change to this plugin's own entries.

### Fixed

- Shared library comments that restated Claude Code hook, plugin and managed-settings behavior now point at the live docs sections, and the prerequisites probe no longer gives a wrong reason for always exiting 0.

- **One install hook and `pydeps.py` across animation, speech and explainer-video.** Both are now generated copies of `lib/install-python-deps.sh` and `lib/pydeps.py`, kept in step by `scripts/sync-shared-copies.sh`, with each plugin's settings in `hooks/install-python-deps.conf` and `scripts/pydeps.json`. The explainer-video fixes reach animation and speech: the handover to a supported Python drops a foreign `PYTHONHOME`, `PYTHONPATH` and uv marker, Windows finds a python.org install through `py -0p`, a crashed handover is a one-line notice with a repair line, and `pydeps.py check` reports the install.

- **The shared prerequisites checker now finds a `python-pkg` in the plugin's own installed Python
  set.** A module that the interpreter cannot import on its own is looked up in the set a plugin
  with a committed `requirements.txt` installs into its data directory
  (`<data>/python/<lock hash>-<interpreter tag>/`), imported the way that plugin's launcher runs
  it. Before, such a package was reported missing. When the data directory is unknown (no
  `--data-dir`, no `CLAUDE_PLUGIN_DATA`), the entry reports `unverified` instead of failing.
  Refs #6112.

### Security

- **Files in the project no longer run inside `pydeps.py`.** The version probe runs isolated (`-I`), the load probe and pip run without the working directory on the module path (`-P`), and on Windows the interpreter search skips the working directory, so a `python3.bat`, `sysconfig.py`, `numpy.py` or `pip` package in the project is never run.

## [0.2.11] - 2026-10-11

### Changed

- **Shared `exec-bash.mjs` launcher synced; no change to this plugin's hooks.** The launcher gains `--run-if-any-set`, `--run-if-settings-mention`, `--skip-unless-marker` and `--marker-root`, which the autonomy and disk-hygiene Stop rows use to skip starting bash on a turn where their script would exit at once.

## [0.2.10] - 2026-10-07

### Changed

- **Upstream records ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** The shared `hook-utils.sh` copy picks up recheck triggers on its upstream records.

## [0.2.9] - 2026-10-04

### Changed

- **Shared `hook-utils.sh` synced; no change to this plugin's hooks.** Two comments no longer cite the retired statusline tee.

## [0.2.8] - 2026-10-04

### Changed

- **Python package notices go to the user only (#6225).** The SessionStart notices for a missing Python or a failed package install are shorter and no longer reach the model: `/explainer-video:produce` prints the repair line itself when it runs.

## [0.2.7] - 2026-10-04

### Changed

- The SessionStart node-notice rows now match `startup|resume|clear|fork`, so a compaction no longer starts them; the session and its notice latches survive a compaction, so a re-fire printed nothing (#6251).
- The shared `exec-bash.mjs` launcher copy gains the `--skip-if-all-false` and `--skip-unless-stdin-contains` flags; no row in this plugin uses them (#6252, #6253).

### Fixed

- The `pydeps.py` helper is now passed to native Python as a Windows path (#6250).

## [0.2.6] - 2026-10-04

### Changed

- **Shared `hook-utils.sh` synced ([#5924](https://github.com/melodic-software/claude-code-plugins/issues/5924)); no change to this plugin's hooks.**

## [0.2.5] - 2026-10-04

### Changed

- **Shared hook notice text ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)).** Skip notices from the shared hook helpers are never renewed: each tells the model once per agent and the user once per session, and says the notice will not repeat. A missing-tool notice no longer carries the hook's PATH; that goes to the debug log. The SessionStart notice for a missing node goes to the user only, in one shorter line.

## [0.2.4] - 2026-10-04

### Fixed

- **On Windows, `pydeps.py` finds a Python 3.12 or 3.13 that is registered with the `py` launcher but not on PATH** ([#6186](https://github.com/melodic-software/claude-code-plugins/issues/6186)).
  The python.org installer puts no `python3.13.exe` on PATH, so when another Python such as uv's 3.14 owned `python3`
  and `python`, the install the `SessionStart` message suggests still left no interpreter to hand over to. After the PATH
  names, `pydeps.py` now probes each `python.exe` that `py -0p` lists, with the same `PYTHONHOME` and `PYTHONPATH` scrub
  as the handover. The listing launches nothing, so the Python install manager never installs a runtime as a side effect.
  Under Git Bash or Cygwin, when no `python` is on PATH, the hook asks `py` only for `py -0p` and starts `pydeps.py` with a
  listed `python.exe`, a 3.12 or 3.13 one first; when `py` lists none, it gives the missing-Python notice and launches
  nothing, since a `py` launch with no runtime installed installs one. `/explainer-video:check` falls back to a listed
  `python.exe` the same way. `prerequisites.json` declares the launcher as an optional `py-launcher` entry
  with no version probe, so the prerequisite check only looks for it and never launches it.
- **A free-threaded Python 3.13 (`python3.13t.exe`) is no longer taken for a supported one.** ModernGL publishes no
  `cp313t` wheel, so its install failed even when a regular 3.13 came later in the list. The probe now skips a build with
  `Py_GIL_DISABLED` set, on PATH and in the `py -0p` listing, and `pydeps.py` refuses to install under one.

## [0.2.3] - 2026-10-04

### Fixed

- **`pydeps.py` no longer passes its own `PYTHONHOME` and `PYTHONPATH` to the Python it hands over to** ([#6162](https://github.com/melodic-software/claude-code-plugins/issues/6162)).
  Started from a uv-managed Windows trampoline, it forwarded that trampoline's `PYTHONHOME`, so the 3.12 or 3.13
  it handed over to loaded the other version's standard library and died on its first import. The candidate probe and
  the handover now drop `PYTHONHOME`, `PYTHONPATH` and every `UV_INTERNAL__*` marker. When the handed-over Python still
  crashes, the `SessionStart` notice carries the traceback's last line and the repair line instead of the traceback.

## [0.2.2] - 2026-10-03

### Fixed

- **The `SessionStart` node-notice row no longer runs `powershell` on Linux.** It stopped at `${BASH_VERSION:+exit}`, which only bash sets; Claude Code runs hooks with `/bin/sh`, which is dash on Debian and Ubuntu (WSL included), so every session printed `powershell: not found`. The row now stops at `${PPID:+exit}`, which every POSIX shell sets.

## [0.2.1] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.2.0] - 2026-10-03

### Added

- **Narrated videos, audio first** ([#5862](https://github.com/melodic-software/claude-code-plugins/issues/5862)).
  `produce` writes a narration script (one paragraph per beat) and narrates it with `/speech:narrate`;
  `scripts/narration.py` turns the script's paragraphs and `words.json` into beat start times, and a
  scene's `beat(self, k)` calls hold until each one. `render.py --narration <folder>` muxes the silent
  render with the narration (AAC) and a caption track built from `words.json` (`mov_text`, also
  written as `captions.srt`), and fails the run when a beat misses its narration start by more than
  one frame, when the file does not hold one video, one audio and one subtitle stream, or when the
  video and audio streams differ by more than a frame per animation plus one.
- Without the `speech` plugin, `produce` renders silent and says narration is unavailable; `beat`
  then holds only its `hold` seconds, so one scene serves both.

## [0.1.3] - 2026-10-03

### Changed

- **Shared `hook-utils.sh` synced ([#5838](https://github.com/melodic-software/claude-code-plugins/issues/5838)); no change to this plugin's hooks.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

## [0.1.2] - 2026-10-03

### Changed

- **SessionStart reports a missing node.** One shell-form row runs the shared node-notice, and shared `hook-utils.sh`, `prerequisites.sh`, `prerequisites.ps1` are synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)).

## [0.1.1] - 2026-10-03

### Changed

- **Shared `exec-bash.mjs` synced ([#5837](https://github.com/melodic-software/claude-code-plugins/issues/5837)); no change to this plugin's hooks.**
  It is now generated from the repository's canonical source by `scripts/sync-shared-copies.sh` and opens with a header saying so; edit
  the canonical, not the copy.

## [0.1.0] - 2026-10-02

### Added

- The `produce` skill: plans the beats of a short explainer, writes one ManimCE scene script, renders
  it at low quality with `scripts/render.py`, and re-renders until every check passes and the frames
  read clean ([#5861](https://github.com/melodic-software/claude-code-plugins/issues/5861)).
  `render.py` fails the run on a wrong stream layout or duration (ffprobe), a blank frame while
  something is on screen, overlapping text, or an element cut off by the frame edge, and extracts a
  frame after every animation for the skill to read back.
- The `check` skill: read-only PASS/FAIL rows for Python 3.12 or 3.13, ManimCE, ffmpeg and ffprobe.
- A `SessionStart` hook that installs the hash-locked `requirements.txt` (ManimCE 0.21.0 with Typst)
  into the plugin data directory through `scripts/pydeps.py`, and `prerequisites.json` declaring
  node, Python, ffmpeg and ffprobe.
