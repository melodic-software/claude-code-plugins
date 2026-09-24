# animation

A Claude Code plugin for hand-drawn-style 2D animation made as code. Scenes are deterministic
Canvas 2D modules (`renderFrame(t)`), headless Chromium draws the frames, and ffmpeg encodes them.

## Skills

| Skill | What it does |
|---|---|
| `/animation:rotoscope <clip> <work dir>` | Copies a reference clip drawing by drawing: traces each distinct drawing to vector paths, renders them through the ink.js brush engine, measures every drawing against its source (XOR against a codec-noise floor, SSIM, edge-band SSIM, paper colour), fits per-shot brush overrides, and reviews 1:1 crops. Each run appends to a learnings file, and a retro step promotes recurring findings into the defaults. |
| `/animation:learn-style <work dir> <pack dir>` | Measures a rotoscope work directory into a style pack: palette and tone ramp, the seven style knobs, and statistic bands (edge softness, stroke and gap widths, edge roughness, gray inside the ink, boil between held drawings, holds on 1s/2s/3s). Then proves the pack by authoring a new scene with ink.js and checking its render against the bands. |

Planned next: `film` (brief, boards for approval, shots, render, review).

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
named by `?scene=`), and `capture.mjs` (saves each drawing or every frame at a given fps as PNG), and `inkstats.py` (style
statistics of any film, a video, a frame folder or a rotoscope work dir, with `--pack` to check it
against a style pack).

## Requirements

- Python 3 with numpy and opencv, run through `uv run --with numpy,opencv-python-headless`.
- `ffmpeg` and `ffprobe` on PATH.
- Node and playwright-core with Chromium. `capture.mjs` looks in `PW_CORE`, then the working
  directory, then a playwright-cli install on PATH, and prints the remedy when none is found.

## Regression

The shfred0 study is the calibration target: 239 drawings, each within 1.2x its codec-noise floor
on XOR and at least 0.980 SSIM. Its per-shot override file ships as a fixture (parameters only; the
clip and traces are not shipped). With the clip and an empty directory:

```bash
uv run --with numpy,opencv-python-headless python \
  plugins/animation/skills/rotoscope/scripts/regress.py <shfred0.mp4> <empty work dir>
```

It exits 0 only on 239/239.
