# Changelog

All notable changes to the `explainer-video` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
