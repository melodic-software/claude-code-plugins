---
description: "Build animated pixel-art scenes as one self-contained HTML file (Canvas 2D, no libraries, no external assets): cutscenes, title screens, dialogue beats, ambient loops, short pixel films, card reveals, and backgrounds with parallax, particles, lighting by palette steps, bitmap text and dither transitions. Reuses sprite specs from /pixel-art:sprite and /pixel-art:animate, takes an optional audio file, and reviews itself through browser screenshots when a browser tool is present. Use when: 'pixel-art scene', 'cutscene', 'title screen', 'animated pixel background', 'pixel-art short', 'make it a little pixel-art movie', 'intro sequence', 'ambient loop'. Not for a single sprite (use /pixel-art:sprite), a sprite sheet for an engine (use /pixel-art:animate), or hand-drawn or ink-style animation and a general video file."
argument-hint: "<scene description> [resolution] [duration] [audio file]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Author, render, and review a self-contained HTML pixel-art scene
---

# Scene

Compose a moving pixel-art scene the user opens in any browser.

## 1. Brief

Follow [`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md): the shared fields, the `brief.md`
file before the first build, one-line defaults, and the presence-gated `/planning:interview`
offer (planning owns a numbered-question brief; the in-skill brief is the fallback and the
default). Then add:

- **Beats**: what happens, in order, and how long each lasts; loop or play once.
- **Cast and set**: characters (existing sprite specs or new ones), location, time of day.
- **Resolution**: a fixed logical size such as 160x144, 240x160, 320x180; everything is drawn
  there and integer-scaled.
- **Audio**: none, or a WAV path / audio artifact from another tool, passed in explicitly.

Mood, palette, style references, and proportions still come from the shared brief and apply to
the cast. When view does not apply, default it to "scene" in the defaults line.

When a cast member is an existing spec with `brief.md` beside it, read that file and extend it.
Do not re-ask fields it answers. Write this scene's `brief.md` beside the scene template before
the first build.

## 2. Author

Follow [`scene-canvas.md`](${CLAUDE_PLUGIN_ROOT}/reference/scene-canvas.md). Write a template HTML
file beside the output:

- Characters come from sprite specs: embed them with `/*EMBED:relative/path.json*/null` and build
  one offscreen canvas per frame at load, so sprites stay the same source the engine sheet uses.
  Missing characters: author them first with `/pixel-art:sprite` or `/pixel-art:animate`.
- Beats are a timeline or state machine driven by a fixed 60 Hz step; sprite cadence stays 8 to 12
  fps; every draw lands on integer coordinates.
- Light and fades step through palette colors or Bayer-dither patterns; never alpha, gradients or
  blur.
- Audio, when given: put `/*WAV:relative/file.wav*/null` in the template. `embed.py` inlines a
  `data:audio/wav;base64,...` URL (the output stays one file). Play it with WebAudio: this plugin starts
  it on the first click and rewinds the scene clock on that click, so the picture and the loop
  share a start. Browser behavior and its record: `scene-canvas.md` Audio.

A worked example is `${CLAUDE_PLUGIN_ROOT}/examples/campfire/scene.html` (title card, dithered sky,
parallax, fire particles, walking character, typed dialogue); copy the folder into the working
directory before adapting it.

Expose `window.__pixelScene` as [`scene-canvas.md`](${CLAUDE_PLUGIN_ROOT}/reference/scene-canvas.md)
describes under Review capture (`seek`, `frameDataURL`, `play`, `duration`) so the review command
can land on a timeline point.

Then inline the embeds into one file:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/embed.py" <template.html> <out-dir>/<name>.html
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <out-dir>
```

## 3. Review loop

Run one command. It serves a copy of the self-contained scene (nothing beside it) and, when a browser is on `PATH`, seeks the
timeline and writes shots (and a WebM when `--record` is set):

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/capture.py" <out-dir>/<name>.html --at 0,1.5,6 --record 4 --out <out-dir>/capture
```

Exit 0: read each `shot-<n>.png` and, when present, treat `scene.webm` as the shareable video-only recording.
Every round, list each done criterion in `brief.md` as pass or fail with a one-line reason, and
check silhouettes against the background, palette contrast, beat timing, text legibility, stray
non-integer or smoothed pixels. Fix, rebuild, re-run the same command. Stop when every done
criterion passes, or after the round budget (typically 2 to 4) with the failing criteria named.

Exit 3 means no Chrome or Chromium on `PATH` (set `CAPTURE_BROWSER` to a browser binary, such as
Playwright's Chromium, to point it at one). When a browser automation tool is present instead (a
Playwright CLI or MCP, the built-in browser tools), serve the output directory over
`http://127.0.0.1:<port>/`, call `window.__pixelScene.seek(t)` at the same timeline points, take
the screenshots with that tool, and review them as above. With neither, exit 3's
`visually unreviewed` stands. Say that the scene is visually unreviewed. Do not claim it
looks right. Check the script parses (`node --check` on the extracted script when Node is
present), grade whatever criteria the script can speak to, mark the rest fail with the reason
"not seen", and ask the user to open it and describe what they see.

## 4. Deliver

Report the HTML path, the gallery `index.html`, and when capture wrote one, `scene.webm`, as full
paths, converted to a host path when the session runs in WSL (`wslpath -w`). A GIF export of a
scene is not produced here: GIF carries no audio and the scene is code. `--record` writes video
only unless the scene exposes a gesture-free `window.__pixelScene.audioStream` aligned to the seek
clock. The campfire example does not (its audio starts only on a click that `capture.py` never
sends), so its WebM is silent. Audio in the recording is not supported yet.

## Next

/pixel-art:animate to add or fix a cycle a scene character needs.

## Gotchas

- Browser automation tools may refuse `file:` URLs (the Playwright CLI blocks the protocol), which is
  why review goes through a localhost server. A Linux browser also needs its system libraries; a
  launch error naming a missing `.so` means those are not installed, not that the scene is broken.

- `image-rendering: pixelated` plus `imageSmoothingEnabled = false` both matter; either alone
  smooths somewhere.
- Per-pixel dithered relighting over a whole scene tends to look washed out; flat colors per tile
  with a highlight and a shadow edge read better.
- The WebAudio square oscillator is fixed at 50% duty; chip-style duties need a `PeriodicWave` or
  sample buffers.
