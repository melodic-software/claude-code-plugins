# Changelog

All notable changes to the `pixel-art` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.6.8] - 2026-10-07

### Changed

- **Upstream records ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** Verification records carry recheck triggers specific to each claim, and citations of retired code.claude.com pages or drifted claims point at the live sections.

## [0.6.7] - 2026-10-07

### Changed

- **Docs links ([#6498](https://github.com/melodic-software/claude-code-plugins/issues/6498)).** Citations of the retired `plugins-reference` and `discover-plugins` pages now point at the live pages that took over each section (`plugins/manifest-reference`, `plugins/components`, `plugins/cli-reference`, `plugins/loading`, `plugins/install`, and `settings-reference#pluginconfigs`). Quotes that moved with them are updated, and each re-verified pointer carries an as-of date of 2026-10-07.

## [0.6.6] - 2026-10-04

### Fixed

- **`capture.py` waits up to 60 s for each browser step on a slow host, and a timeout names the step ([#6219](https://github.com/melodic-software/claude-code-plugins/issues/6219)).** Opening the page had 10 s, the debugger connection 20 s, the scene's readiness 15 s, and the capture its recording length plus 20 s (30 s at least); a contended CI runner ran past them with the browser still alive, and the run failed with a bare `timed out`. Each now has 60 s, the capture its recording length plus 60 s, and the error reads, for example, `opening the scene page: timed out`. The campfire test puts capture.py's error ahead of the browser log in its failure message; the log's headless D-Bus lines were read as the cause.

## [0.6.5] - 2026-10-04

### Changed

- **Shared `prerequisites` checker copies synced ([#6225](https://github.com/melodic-software/claude-code-plugins/issues/6225)); no change to this plugin's behavior.**

## [0.6.4] - 2026-10-04

### Changed

- **Upstream plugin doc links repointed to the split `plugins/` pages ([#5962](https://github.com/melodic-software/claude-code-plugins/issues/5962)).** The README options block now links `plugins/cli-reference#plugin-install` for the `--config` flag, since the old `plugins-reference` page no longer carries that section, and `plugins/manifest-reference#user-configuration` for the `userConfig` schema.

## [0.6.3] - 2026-10-03

### Changed

- **Shared `prerequisites.mjs` synced ([#6084](https://github.com/melodic-software/claude-code-plugins/issues/6084)); no change to this plugin's lib.**
  The prerequisite check now counts a Windows App Execution Alias (a Store or winget install on PATH) as found,
  except App Installer's Python install stub. A `cli` or `runtime` entry can set `reject_store_alias` to skip aliases instead; no entry in this plugin does.

## [0.6.2] - 2026-10-03

### Changed

- `scripts/backends.test.sh` declares the files it reads without naming them in a `# test-scope:` header, so CI's test selection runs it when one of them changes. Nothing the plugin runs changed.

## [0.6.1] - 2026-10-03

### Changed

- Shared `prerequisites.sh`, `prerequisites.ps1` synced ([#5843](https://github.com/melodic-software/claude-code-plugins/issues/5843)); no change to this plugin's own behavior.

## [0.6.0] - 2026-10-02

### Added

- `prerequisites.json`, declaring the external tools this plugin runs and what stops working
  without each, and the generated `lib/prerequisites.mjs` checker with its `.sh` and `.ps1`
  stubs that read it ([#5842](https://github.com/melodic-software/claude-code-plugins/issues/5842)).

## [0.5.2] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.5.1] - 2026-10-02

### Fixed

- `capture.py` waits up to 60 seconds, not 20, for a running browser to open its debugger port. A
  cold first browser launch on a busy CI runner passed 20 seconds while the browser was still
  starting, which failed the campfire capture test with "browser did not open a debugger port". A
  browser that exits still fails at once.

## [0.5.0] - 2026-10-02

### Changed

- The `backend` option is a picker in `/config` (`native`, `aseprite`) per the plugin option
  naming convention (`docs/conventions/plugin-option-naming/`), so a value outside that set is no
  longer accepted. Its description now names what each value does.

## [0.4.1] - 2026-10-01

### Changed

- The README and `backends.md` describe the Aseprite adapter as best-effort and unverified against a real
  Aseprite install, with a failed run, missing output or a `sheet.json` without frames or meta falling back to native, in place of the local stand-in status line.

## [0.4.0] - 2026-09-29

### Added

- `capture.py --record` muxes the scene's `audio` WAV under the WebM with ffmpeg, looped from scene time 0
  and trimmed to the recording length, so the campfire recording has an audio track matching the video
  length. Without ffmpeg, or when ffmpeg cannot mux (for example a build without libopus, a stalled run, or an empty output), the recording
  stays video-only, `capture.py` prints a note, and the manifest says so (#5282).

### Changed

- `scene-canvas.md` and the `scene` skill document the `audio` hook and the ffmpeg mux in place of the
  video-only statement.

## [0.3.8] - 2026-09-29

### Removed

- The PixelLab and Retro Diffusion adapters, `hosted_backends.py`, the `--confirm` flag and
  `PIXEL_ART_BACKEND_CONFIRM`. The backend is `native` (default) or `aseprite`; an unknown
  configured name falls back to native with a notice. Hosted generators can return as separate items.

## [0.3.7] - 2026-09-29

### Changed

- `tileset`, `ui`, and `vfx` render through `backends.py` and follow `reference/brief.md` for the
  shared brief fields, matching `sprite` and `animate` (#4400, #4402).
- The Aseprite adapter rewrites its `sheet.json` to the native contract: frame keys are the spec
  frame names and `meta.image` is `sheet.png`. A frame-count mismatch falls back to the native
  renderer with a notice, and `frameTags` indexes follow the compacted frame map (#4402).
- `tileset`, `ui`, and `vfx` stay on native unless the request or `${user_config.backend}` names
  another backend.
- `backends.md` and the README state that the adapters have run only against local stand-ins.
- The click-to-start audio rule in `scene` is recorded with its basis in `scene-canvas.md`. The
  docs say `--record` writes video only, so the campfire WebM is silent (#4404, #4403).
- `sprite` points at `scripts/kit.py` for full-body humanoids. `AUDIO.txt` no longer cites
  `retro-audio` script paths, and `brief.md` drops two records that backed no rule (#4405, #4404,
  #4399).

### Fixed

- `capture.py --record` rejects `inf`, `-inf`, and `nan` instead of hanging (#4403).
- `backends.test.sh` runs every `test_*.py` suite; only `test_backends.py` ran in CI before.
  New browser-free tests cover capture cleanup, the video-less default, and the served copy.

## [0.3.6] - 2026-09-28

### Added

- `scripts/kit.py`: proportion presets (`chibi`, `standard`, `tall`), head and hair shapes,
  clothing layers, material ramps, top-left shading, a selective outline, and 4-direction
  handling. `examples/walker/blacksmith.py` is a walker built on the kit, covered by
  `scripts/test_kit.py` (#4405).

## [0.3.5] - 2026-09-28

### Added

- Evals for vague briefs on `sprite`, `animate`, and `scene`, a PICO-8 and a Godot layout
  case, and a scene case that refuses to claim a visual review without a browser tool (#4406).

### Changed

- Reference review: Godot 3 bitmask pairings are judgment (the docs and Godot issues #64769 and
  #79411 disagree). The Aseprite section adds the EULA license shape from the FAQ.
  `image-rendering: pixelated` is cited from MDN. Unity no longer states unverified facts.

## [0.3.4] - 2026-09-28

### Added

- `scripts/backends.py` runs the selected backend and falls back to native with one line when it
  is missing or unconfirmed (#4402). Aseprite is `aseprite --batch --script` plus a json-hash sheet
  export. PixelLab (`POST /v1/generate-image-pixflux`) and Retro Diffusion (`POST /v2/inferences`)
  snap generated pixels through `scripts/image_pipeline.py` before the native render. Paid calls
  wait for `--confirm`. `reference/backends.md` records the flags and endpoints that were checked
  against the vendor pages on 2026-09-28.

## [0.3.3] - 2026-09-28

### Added

- `scripts/capture.py`: one command serves a scene, seeks `window.__pixelScene` to the given
  timeline points, and writes PNG shots. `--record` asks the page to record a WebM with
  `MediaRecorder` when the scene has a canvas stream. Exit 3 means no browser tool was present,
  so the scene stays visually unreviewed (#4403).
- The campfire example exposes `seek`, `frameDataURL`, and `play` for that command, and its
  audio stream as `audioStream` once the first click starts the loop.

## [0.3.2] - 2026-09-28

### Added

- `embed.py` inlines `/*WAV:file.wav*/null` as a `data:audio/wav;base64` URL. The campfire scene
  plays `examples/campfire/campfire.wav` on the first click and rewinds its clock so the picture
  and the loop start together. The WAV is an artifact; this plugin does not import the tool that
  rendered it (#4404).

## [0.3.1] - 2026-09-28

### Added

- `tileset`, `ui`, and `vfx` skills. Tilesets cover terrain, autotiles (RPG Maker MZ A1-A5 and B-E,
  blob-47, and 16-tile corner sets), backgrounds, and parallax. UI covers window skins, icon sets,
  HUD elements, and bitmap fonts. VFX covers sparks, spells, explosions, and other cell sheets,
  including MV-style `img/animations`. Effekseer (`.efkefc`) stays out of scope.
- Worked generators under `examples/tileset`, `examples/ui`, and `examples/vfx`, rendered by
  `scripts/render.py`. Tests check an MZ A2 sheet, a `Window.png` skin, and a five-column animation
  sheet against the grids in `engine-layouts.md` (#4400).

## [0.3.0] - 2026-09-28

### Added

- Bundled palette presets in `palettes/`: `pico-8`, `nes` (jsnes NTSC table), `game-boy` (mGBA
  DMG Green), and the CC0 Lospec sets `retro-8-bit`, `deep-sea`, and `cosmic-space` (#4401). Each
  file records its source and license. A spec `palette` string names a preset or a project palette
  file; the inline object form is unchanged.
- `render.py --snap` maps an 8-bit RGB or RGBA PNG onto a palette (nearest sRGB color, alpha below
  128 transparent). `--dither` adds 4x4 Bayer ordered dither. `--emit-frames` writes spec rows.

## [0.2.0] - 2026-09-28

### Added

- `reference/brief.md`: the shared brief fields (including style references, proportions, and 2 to 6
  done criteria). `sprite`, `animate`, and `scene` write that brief beside the spec before the
  first render, re-read it on a later run, and mark each criterion pass or fail every review round.
- A presence-gated offer of `/planning:interview` for a vague or high-stakes request. The in-skill
  brief remains the default and works with nothing else installed.

## [0.1.1]

### Changed

- `animate` and `scene` descriptions exclude hand-drawn or ink-style animation and general video
  output, and their trigger phrases name pixel art, so they no longer claim the `animation`
  plugin's requests.

## [0.1.0]

### Added

- `sprite`, `animate` and `scene` skills: brief, author, render, review loop, deliver.
- `scripts/render.py`: standard-library renderer from a palette-locked spec to a 1x sheet PNG,
  an upscaled preview, one looping GIF per animation, and frame data in the Aseprite json-hash shape.
- `scripts/embed.py` inlines sprite specs into a scene template; `scripts/gallery.py` writes a
  preview page for an output directory.
- Reference files: static and animation craft rules, tiles, engine layouts (RPG Maker MZ, Aseprite,
  Godot, PICO-8, Pyxel), HTML Canvas scene rules, and the backend contract.
- `output_dir` and `backend` settings.
