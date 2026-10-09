# Changelog

All notable changes to the `explainer-video` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
