---
description: "Build animated pixel-art scenes as one self-contained HTML file (Canvas 2D, no libraries, no external assets): cutscenes, title screens, dialogue beats, ambient loops, short pixel films, card reveals, and backgrounds with parallax, particles, lighting by palette steps, bitmap text and dither transitions. Reuses sprite specs from /pixel-art:sprite and /pixel-art:animate, takes an optional audio file, and reviews itself through browser screenshots when a browser tool is present. Use when: 'pixel-art scene', 'cutscene', 'title screen', 'animated pixel background', 'pixel-art short', 'make it a little movie', 'intro sequence', 'ambient loop'. Not for a single sprite (use /pixel-art:sprite) or a sprite sheet for an engine (use /pixel-art:animate)."
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

Pin down, from the request or by asking (defaults stated in one line when unspecified):

- **Beats**: what happens, in order, and how long each lasts; loop or play once.
- **Cast and set**: characters (existing sprite specs or new ones), location, time of day, mood.
- **Resolution**: a fixed logical size such as 160x144, 240x160, 320x180; everything is drawn
  there and integer-scaled.
- **Palette**: locked, typically 16 to 32 colours.
- **Audio**: none, or a WAV path / audio artifact from another tool, passed in explicitly.

## 2. Author

Follow [`scene-canvas.md`](${CLAUDE_PLUGIN_ROOT}/reference/scene-canvas.md). Write a template HTML
file beside the output:

- Characters come from sprite specs: embed them with `/*EMBED:relative/path.json*/null` and build
  one offscreen canvas per frame at load, so sprites stay the same source the engine sheet uses.
  Missing characters: author them first with `/pixel-art:sprite` or `/pixel-art:animate`.
- Beats are a timeline or state machine driven by a fixed 60 Hz step; sprite cadence stays 8 to 12
  fps; every draw lands on integer coordinates.
- Light and fades step through palette colours or Bayer-dither patterns; never alpha, gradients or
  blur.
- Audio, when given: load it from the path the user named with WebAudio, started on the first click
  (browsers block autoplay), cues tied to the same timeline.

A worked example is `${CLAUDE_PLUGIN_ROOT}/examples/campfire/scene.html` (title card, dithered sky,
parallax, fire particles, walking character, typed dialogue); copy the folder into the working
directory before adapting it.

Then inline the embeds into one file:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/embed.py" <template.html> <out-dir>/<name>.html
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <out-dir>
```

## 3. Review loop

With a browser automation tool present (a Playwright CLI or MCP, the built-in browser tools),
open the file, capture screenshots at several timeline points, read them, and critique: silhouettes
against the background, palette contrast, beat timing, text legibility, stray non-integer or
smoothed pixels. Fix, rebuild, re-capture; typically 2 to 4 rounds. Without one, say that the scene
is unreviewed visually, check the script parses (`node --check` on the extracted script when Node
is present), and ask the user to open it and describe what they see.

## 4. Deliver

Report the HTML path and the gallery `index.html`, converted to a host path when the session runs
in WSL (`wslpath -w`). A GIF export of a scene is not produced here: GIF carries no audio and the
scene is code; offer screen recording in the browser when the user needs a video.

## Next

/pixel-art:animate to add or fix a cycle a scene character needs.

## Gotchas

- `image-rendering: pixelated` plus `imageSmoothingEnabled = false` both matter; either alone
  smooths somewhere.
- Per-pixel dithered relighting over a whole scene tends to look washed out; flat colours per tile
  with a highlight and a shadow edge read better.
- The WebAudio square oscillator is fixed at 50% duty; chip-style duties need a `PeriodicWave` or
  sample buffers.
