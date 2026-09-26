# Rotoscope method and defaults

Every number here comes from `measure.py` runs on the shfred0 study (239 drawings, 1762x982,
h264), rendered in headless Chromium and compared at 1:1. Treat them as the current defaults, not
laws: a new source with a different codec, scale or ink can move them, and the retro step in
`SKILL.md` is how they change.

## Contents

- Source analysis
- Tracing
- Rendering (mode b)
- Target and what limits it
- Diagnostics, in the order to read them
- Reviewing images
- Known limits

## Source analysis

- Drawings, not frames: a stored frame that changes too few pixels by a large gray step repeats
  the previous drawing (`scripts/decode.py`, `is_repeat`, holds the counts). A mean-difference
  dedup wrongly drops real drawings such as a small caption change of about 1,000 pixels.
- Gray is RGB2GRAY. T is the midpoint of the ink and paper gray modes (shfred0: 17 and 234, so
  T = 125.5 on every drawing).
- Soft edges: shfred0 is blurred by about sigma 0.85 px, isotropic.

## Tracing

- `findContours` returns boundary-pixel centres, so a polygon through them sits 0.5/S px inside
  the true edge, and a 1 px line has zero area at S=1. Supersample (`extract.py` `S`, `INTERP`) before
  thresholding, then correct the leftover inset with render-side `bias`.
- `approxPolyDP` epsilon `EPS` (`extract.py`, in source px). Epsilon 0 is worse: the raw staircase plus the bias ring
  over-fattens. S=8 gains nothing over S=4 and doubles the point count.
- Unsharp mask (`extract.py` `SHARP`: amount, sigma) before tracing undoes the source blur, so render-side blur
  puts thin lines back at the right darkness. It is only correct together with render blur.
- The unsharp mask keeps the raw gray on the outer 1 px frame border. Otherwise the blur reflects
  the dark row 1 onto row 0 and pushes a near-T border row (gray about 110-120) past T, which
  traces a 1 px paper run along every frame edge that touches ink. Measured over 239 drawings:
  mean XOR 0.2262 to 0.2217 %, worst XOR/floor 1.18 to 1.16, edge-band SSIM +0.0002, and no
  drawing worse than +0.003 pp.
- Do not judge tracing with cv2 `fillPoly`: it fills every pixel an edge touches, and its bias
  grows with S. Measure in the browser.

## Rendering (mode b)

- Tone layers: the same tracer runs at the gray levels `extract.py` `LEVELS` lists, and each layer
  is filled with its band's median RGB. This captures dry-brush streaks and the soft edge ramp. Six
  levels add about 0.001 SSIM for about 1.4x the points.
- The brush defaults are in `scripts/brush.json`, which `roto.js`, `measure.py` and `fit.py` all
  read. `bias` (px): a ring of ink.js `capsule` dabs of width 2 x bias on the T contour. `blur`
  (sigma, px): a JS separable gaussian, because of the floor below.
- Chromium's canvas blur floor. Claim: `ctx.filter = 'blur()'` silently does nothing below about
  0.8 px. Basis: a Playwright capture of a blurred two-tone canvas. As of: 2026-09-24, Chromium
  build 1246. Recheck trigger: the Chromium build `render.json` records changes.
- Brush texture does not help a traced copy: an `inkStroke` ring, wobble and dry-brush all
  measured slightly worse than capsules, and `paperGrain` lowers SSIM (uncorrelated grain). The
  source's texture is already in the traced geometry.

## Target and what limits it

Per drawing: XOR <= 1.2 x floor, SSIM >= 0.980, edge-band SSIM >= 0.980. The floor is the % of
source pixels within 4 gray levels of T: codec noise decides which side of T they fall on, and no
copy can predict it. 91-100% of the residual XOR pixels sit in a near-T band. Dense line work has
more edge per ink pixel, so its floor is higher (0.35-0.70% against 0.02-0.25%). SSIM is limited
by codec block noise on flat fills, paper specks lighter than the lightest tone level, and the
quantized tone ramp.

## Diagnostics, in the order to read them

1. **Replica-only / source-only ratio** (measure table), before any image. Far from 1:1 across a
   whole shot means the bias is wrong for that shot, not that one drawing is broken. Above the
   ratio band re-render at a larger bias, below it at a smaller one; `fit.py` automates this (its
   `--ratio` and `--step` hold the band and the step). Bias moves
   pixels between the two error colours and barely changes total XOR when the real problem is blur
   or sharpening.
2. **Ratio stuck near 2 while a bias sweep does nothing**: suspect over-sharpening on dense dashes.
   Sweep `sharp` sigma before bias (shfred0 skyline: sigma 0.6 instead of 0.9 took XOR/floor from
   1.12 to 0.84). Wider tone spacing (40, 80, 170, 215) helped the same dense drawings.
3. **Near-all-ink or near-all-paper frames**: the floor drops to 0.02-0.05%, and a few hundred
   border pixels decide pass/fail. Signal: source-only 3x replica-only on a low-floor drawing. A
   larger bias (about 0.25) fixes it.
4. **Largest cluster** (review table): a blob (a 4x4 square fits) of one colour is a real miss;
   slivers at most 3 px thick along an edge are coin-flips.
5. **Edge px**: XOR inside the 2 px frame border. A full-frame heatmap hides a 1 px run along the
   edge; this count is what surfaced the border bug.
6. **Tile**: the largest 32 px tile gray difference after a sigma-3 blur. Above 8 means a wrong
   tone inside ink or paper, which XOR cannot see.
7. **paper_err / paper_d**: a tint. One paper colour per drawing cannot follow a spatial tint (a
   pink sign on cream paper differs by under 1 gray level); the `tint` override adds warm-paper
   layers.
8. **Crops**, at 1:1 on the hottest window, for every drawing. Some defects (dash-tip fattening,
   corner rounding) only show zoomed in; scale a crop up, never down.

## Reviewing images

- Long-edge limit for any image read in review (crops, tiled frames). Claim: 2576 px on the long
  edge is the largest image Claude sees without downscaling (Claude 4.7 and later; earlier models
  1568 px), so a wider tile loses the 1:1 detail review needs. Basis: the Claude vision guide,
  "Resolution and token cost" table (<https://platform.claude.com/docs/en/build-with-claude/vision>).
  As of: 2026-09-26. Recheck trigger: that table changes, or review runs on a model outside it.
  `review.py` sizes `CROP` from it (`LONG_EDGE`).

## Known limits

- 1 px paper slits between strokes whose source gray sits near T open inconsistently; the bias
  ring does not close them. A per-hole minimum-width filter is untested.
- Dry-brush streaks darker than the lowest tone level (gray 25-35 against a 50 floor) render flat,
  and SSIM does not register them. A lower tone level would catch them; the target does not need it.
