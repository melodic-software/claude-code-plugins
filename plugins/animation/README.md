# animation

A Claude Code plugin for hand-drawn-style 2D animation made as code. Scenes are deterministic
Canvas 2D modules (`renderFrame(t)`), headless Chromium draws the frames, and ffmpeg encodes them.

## Skills

| Skill | What it does |
|---|---|
| `/animation:rotoscope <clip> <work dir>` | Copies a reference clip drawing by drawing: traces each distinct drawing to vector paths, renders them through the ink.js brush engine, measures every drawing against its source (XOR against a codec-noise floor, SSIM, edge-band SSIM, paper colour), fits per-shot brush overrides, and reviews 1:1 crops. Each run appends to a learnings file, and a retro step promotes recurring findings into the defaults. |
| `/animation:setup` | Checks the prerequisites (ffmpeg with libx264, ffprobe, Node, playwright-core with Chromium, the pinned numpy and opencv, and the `playwright_core` option when set) and prints a PASS/FAIL/INFO table with one remedy line per failure. Check-only: every prerequisite is external. |
| `/animation:learn-style <work dir> <pack dir>` | Measures a rotoscope work directory into a style pack: palette and tone ramp, the seven style knobs, and statistic bands (edge softness, stroke and gap widths, edge roughness, gray inside the ink, boil of the frame and caption, holds on 1s/2s/3s). Then proves the pack by authoring a new scene with ink.js and checking its render against the bands. |

Planned next: `produce` (brief, boards for approval, shots, render, review).

## Style packs

`styles/<name>/` holds one style: `style.json` (measured statistics, bands, knobs, brush defaults)
and `STYLE.md` (the style in words, with its credit and validation). Packs hold statistics only,
never a source's frames or traces.

| Pack | Style |
|---|---|
| `woodcut-ink` | Two-tone brushed ink on cream with carved gouges, a soft edge and boil on 3s. A study of @shfred0's clip; no untraced scene has passed its current check yet. |

## Shared scripts

`scripts/` holds what every skill renders with: `ink.js` (the deterministic brush engine: capsule
dabs, ink fills, strokes, splatter, dashed lines, paper grain), `render.html` (loads a scene module
named by `?scene=`), `render.py` (the one render entry point: serves a scene, captures each drawing
or every frame at a given fps through `capture.mjs`, writes `render.json`, and encodes), `decode.py`
(reads a video, a frame folder or a work dir back into frames), `prereq.py` (the prerequisite
probe), and `inkstats.py` (style statistics of any film, a video, a frame folder or a rotoscope work
dir, with `--pack` to check it against a style pack).

## Requirements

`/animation:setup` checks each of these and prints one remedy line per missing one. Verified on
Linux only; Windows and macOS are untested by hand (the scripts use no shell and open text as
UTF-8, but no run there has been recorded).

- Python 3.12 or later (numpy 2.5 requires it), with numpy and opencv at the versions pinned in
  `requirements.txt`: run every script through
  `uv run --with-requirements ${CLAUDE_PLUGIN_ROOT}/requirements.txt python ...`. The pins keep the
  statistics and the shipped regression reproducible byte for byte.
- `ffmpeg` at or above `scripts/prereq.py`'s `FFMPEG_MIN` (the first release with `-fps_mode`), with
  the `libx264` encoder, and `ffprobe`, on PATH.
- Node and playwright-core with Chromium. `capture.mjs` looks in the `playwright_core` plugin option
  (passed as `render.py --playwright-core`), then the working directory, then a playwright-cli
  install on PATH, and prints the remedy when none is found.

## Regression

The shfred0 study is the calibration target: every drawing within the `measure.py` target (rotoscope
[`reference/method.md`](skills/rotoscope/reference/method.md), Target). Its per-shot override file ships as a fixture (parameters only; the
clip and traces are not shipped). With the clip and an empty directory:

```bash
uv run --with-requirements plugins/animation/requirements.txt python \
  plugins/animation/skills/rotoscope/scripts/regress.py <shfred0.mp4> <empty work dir>
```

It exits 0 only when every drawing passes and the encoded replica passes the woodcut-ink pack.
`regress.py --synthetic <empty dir>` needs no unshipped input: it renders, encodes and re-traces the
committed `fixtures/synthetic.js`.
