# Render backends

Every render goes through `scripts/render.py`, the one place a backend is chosen. Only the native
backend ships today, so `--backend` accepts only `native`; this page holds the rules a second
backend must follow when it is added.

## Contract (every backend honors it)

- In: a scene module (an ES module that sizes `canvas#c`, sets `window.DURATION` and defines
  `window.renderFrame(t)`, optionally `window.renderDrawing(k)`), a frame rate or a drawing list,
  and a query string.
- Out: a frame folder of `fNNNN.png` (frame `i` shows `t = i / fps`) or `dNNN.png` drawings, plus
  `render.json` `{scene, adapter, adapter_version, browser_build, fps, size, frames, duration}`.
- Exit 0 when every frame is written, 1 when the scene fails, 2 when a prerequisite is missing
  (the remedy is printed).

The full contract is sections 2 to 4 of `docs/topics/animation-ports/design/contracts.md` in the
claude-code-plugins repository (not shipped with the plugin).

## Selection rule

`render.py` chooses in the order that contract's section 3, "Composition root", sets out: the backend the skill passes, else native; a chosen backend whose detection fails
prints one line naming what is missing and renders natively; the license notice below; exit 2 only
when native is missing too.

## License rule

A non-native backend's `detect()` returns `(present, version, license_path)`, where
`license_path` is the license file inside the installed package. Before the first render of a
session with that backend, `render.py` prints a notice quoting that installed file, by path and
version, so the user reads the terms they actually have, never a copy kept in the plugin. The
notice states the terms and never judges whether the user qualifies. It prints once per session
and is recorded in `render.json` as `license_notice`, a key absent on native renders.

## Native (default)

- Adds: headless Chromium through playwright-core, captured by `scripts/capture.mjs`; ffmpeg
  encodes the frame folder when `--encode` is given.
- Detect: `scripts/prereq.py` (the rows `/animation:setup` prints); `render.py` stops with exit 2
  and one remedy line when a row it needs fails.
- Cost and license: none beyond the plugin's own; Chromium, playwright-core and ffmpeg are
  installed by the user under their own licenses.
- Contract: defines it. `render.json` records the Chromium build, because pixels can differ across
  builds.
