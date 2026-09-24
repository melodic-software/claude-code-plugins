---
description: "Copy a reference animation drawing by drawing: decode the video into its distinct drawings, trace each to vector paths, render them through the ink.js brush engine in headless Chromium, and measure every drawing against its source (ink/paper XOR against a codec-noise floor, SSIM, edge-band SSIM, paper colour), then fit per-shot brush overrides and review 1:1 crops until every drawing passes. Use when: 'rotoscope this', 'trace this clip', 'copy this animation one to one', 'replicate this video exactly', 'match the reference frame by frame', 'measure the replica against the source'. Not for an original film or a style study without a reference clip."
argument-hint: "<reference video> <work dir>"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Trace, render, measure and fit a 1:1 replica of a reference animation
---

# Rotoscope

Produce a measured 1:1 replica of a reference clip whose pixels come from traced paths and brush
parameters only. Replaying or embedding source bitmaps is out of scope: it is a re-encode and
teaches nothing. Read [`reference/method.md`](reference/method.md) first: it holds the defaults, why
they are what they are, and the diagnostics in the order to read them.

Requirements: Python with numpy and opencv (run the scripts with
`uv run --with numpy,opencv-python-headless python ...`), `ffmpeg` and `ffprobe` on PATH, Node, and
playwright-core with Chromium (`capture.mjs` finds it through `PW_CORE`, the working directory, or
a playwright-cli install; missing, it stops and prints the remedy). The scripts are in
`${CLAUDE_PLUGIN_ROOT}/skills/rotoscope/scripts/`; below, `$R` stands for that folder.

## Work directory

One work directory per reference clip, outside the plugin; it grows to hundreds of MB.

| Path | Written by | Holds |
|---|---|---|
| `src/dNNN.png`, `d/index.json` | `extract.py --video` | distinct drawings; size, duration, `[k, pts, t1]` |
| `d/dNNN.json` | `extract.py` | T-layer paths with holes, tone layers, colours, applied overrides |
| `overrides.json` | you, `fit.py` | per-drawing parameters (below); survives re-extraction |
| `out/<tag>/` | `measure.py`, `review.py` | replicas, heatmaps, `table-*.md`, `review-*.md`, `crops/` |
| `learnings.md` | `measure.py`, you | one line per run, plus your findings |

## Override file

Tool-neutral JSON, the stage artifact that carries every hand decision. Entries apply in file
order to each drawing whose `k` (an index or `[k0, k1]`) holds it; later entries win, and `brush`
merges key by key.

```json
{"overrides": [
  {"k": [0, 30], "brush": {"bias": 0.18, "blur": 0.7}, "why": "sparse line art, replica too thin"},
  {"k": [203, 217], "sharp": [2.0, 0.6], "levels": [40, 80, 170, 215]},
  {"k": [64, 74], "tint": true}
]}
```

`brush` keys: `bias`, `blur`, `grain`, `tones` (see `roto.js`). `sharp` is the unsharp mask
`[amount, sigma]` or `null`; `levels` are the tone gray levels; both retrace. `tint` adds
warm-paper layers. `why` is ignored by the tools and kept for the reader. Geometry never goes in
this file; a fix that needs hand-edited paths is a finding to report, not an override.

## Loop

1. Extract: `$R/extract.py <work> --video <clip>`. After an override change,
   `$R/extract.py <work> --apply` retraces only drawings whose `sharp` or `levels` changed.
2. Measure: `$R/measure.py <work> [--only K0-K1] [--tag name]`. It exits 0 only when every
   drawing meets the target (XOR at most 1.2 x its floor, SSIM and edge-band SSIM at least 0.980).
   Run long ranges in the background.
3. Fit: `$R/fit.py <work> [--only K0-K1]` bisects `bias` per drawing from the replica-only /
   source-only balance, then appends the result to `overrides.json`; apply it with `--apply`. It
   fits bias only: blur, sharpening and tone levels are yours, guided by the diagnostics in
   `method.md`. On shfred0, fitting all 239 drawings from the default bias passes 239/239 at a mean
   XOR 0.3% below the hand fits.
4. Review: `$R/review.py <work> <tag>` adds the manual checks as columns (largest one-colour
   cluster and whether it is a blob, frame-edge XOR, tone-tile difference, paper colour) and writes
   one 1:1 crop per drawing of its hottest window. Read every crop, not only the flagged ones: a
   passing number can hide a visible defect such as a tint. Never downscale a crop or review a GIF.
5. Record: append to `<work>/learnings.md` what failed, the cause, the change and the before and
   after numbers.

Repeat 2-5 by shot or drawing range until the table passes and the crops show no one-colour
cluster.

A film of the replica: serve the work directory, open `render.html?scene=roto.js`, and run
`node ${CLAUDE_PLUGIN_ROOT}/scripts/capture.mjs <url> <frames dir> --fps 24`, then the ffmpeg line
at the top of `capture.mjs`.

## Retro

At the end of a clip, read `learnings.md` next to earlier runs' learnings. A finding that recurs
across shots or clips with the same fix (the same override on most drawings, the same diagnostic
leading to the same change) becomes a default: change the constant in `extract.py` or `roto.js`,
re-run the regression, and record the finding with its numbers in `method.md`. A one-off stays in
the clip's override file.

## Regression

The shfred0 study ships as a fixture (`fixtures/shfred0.overrides.json`, parameters only; the clip
is not shipped). Given that clip and an empty work directory,
`$R/regress.py <shfred0.mp4> <work>` extracts with the fixture, renders and measures every
drawing, and exits 0 only on 239/239. Run it after any change to the scripts.

## Gotchas

- `renderFrame(t)` and `renderDrawing(k)` return Promises; a capture that does not await them
  saves the canvas before the drawing lands.
- Chromium's canvas `blur()` filter does nothing below about 0.8 px, which is why `roto.js` blurs
  in JS; `gauss()` must not add 0.5 before writing to a `Uint8ClampedArray`, which already rounds.
- A drawing JSON is one line of 1-4 MB. Change parameters through the override file and `--apply`,
  never by editing the JSON.
- Gray XOR and SSIM cannot see colour. Read `paper_err` and the crops for tints.
- An all-ink or all-paper frame has a floor near 0.02%; a few hundred border pixels decide it, so
  judge those by the ratio and the edge column, not by the XOR alone.
