---
description: "Learn a drawn animation style from a rotoscoped clip into a style pack: measure its traces and source drawings into knob values and statistic bands (edge straightness and roughness, solid black, boil of the frame and caption, the hold mix on 1s/2s/3s, palette), prove the bands against adversarial controls, then prove the pack by authoring a new scene with ink.js and checking its render against it. Use when: 'learn this style', 'make a style pack', 'extract the style from this clip', 'does my film match the style', 'check this scene against the woodcut pack', 'which statistics separate styles'. Needs a rotoscope work dir; not for copying a clip one to one."
argument-hint: "<rotoscope work dir> <pack dir> [--cuts T,T,..] [--credit TEXT] [--negative SUMMARY.json ...]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Measure a traced clip into a style pack and check new scenes against it
---

# Learn style

Turn a rotoscoped clip into a style pack: the numbers that make the style what it is, and a check
that tells whether a new film shares them. The pack holds statistics only; never copy traced
geometry, source frames or the clip into it. Read
[`reference/statistics.md`](reference/statistics.md) first: what each statistic measures, how a
band is set, which statistics separate the woodcut style from a filtered near miss and from other
styles, and what the check still cannot separate.

Requirements: the plugin README's (run the scripts the way it says; `/animation:setup` checks
them) and a rotoscope work directory (`d/dNNN.json` traces and
`src/dNNN.png` drawings). The scripts are `${CLAUDE_PLUGIN_ROOT}/skills/learn-style/scripts/learn.py`,
`${CLAUDE_PLUGIN_ROOT}/skills/learn-style/scripts/controls.py` and the shared
`${CLAUDE_PLUGIN_ROOT}/scripts/inkstats.py`.

## Pack format

`styles/<name>/` in the plugin, tool-neutral:

| File | Written by | Holds |
|---|---|---|
| `style.json` | `learn.py`, then you | `palette` (ink, paper, tone ramp), `knobs` (the seven-knob schema), `stats` (p10/p50/p90), `timing`, `ref` (the source's values), `bands`, `check`, `measured_only`, `heldout` (how each band was set and how it tested), `brush`, `credit`, `rotoscope_fits` |
| `STYLE.md` | you | the style in words for a reader: credit, knob table with each value marked measured or judgment and pointing at its `style.json` key, how to author in it, the validation result |

`learn.py` measures everything but `credit`, `brush` and the `movement`, `camera` and `backgrounds`
knobs, which it keeps from an existing `style.json`; fill the knobs from viewing the source and mark
them `"basis": "judgment"`. `check` is `learn.py`'s `CHECK`, the statistics shown to separate, less any
content-class row the source defines in fewer than two parts; `measured_only` lists the
subject-sensitive statistics the check prints but never judges. The
numbers live in `style.json` only; STYLE.md and other docs point at its keys.

## Loop

1. Controls: `controls.py measure <out> --near <a near-miss film> --other <films in other styles>
   --source <the clip> --replica <rotoscope work dir>` measures a filtered family of the near miss
   (blur, noise, stripes, dry brush, contour warp), synthetic flat polygons, the other styles, and
   the same-style positives. It alternates the controls between a calibration and an evaluation
   half.
2. Learn: `learn.py <work> <pack dir> --cuts <the clip's shot starts> --credit "<who made the
   source, its URL, date>" --negative <out>/calibration/*.json`. Bands come from film-sized
   excerpts of the source, split by shot, with half the splits held out. The calibration controls
   cap each band's widening so they keep failing.
3. Prove the check: `controls.py check <out> <pack dir>` must show every control failing (margin
   above 0) and the source and replica passing, with the evaluation half held out. Then
   `controls.py selftest <pack dir> --near <the near-miss film>` (the pack argument is required)
   must exit 0. Put the table in `reference/statistics.md`. A control that passes goes under "what the check cannot
   say"; never narrow a band until it fails.
4. Describe: fill the judgment knobs in `style.json` and write `STYLE.md`.
5. Validate: author a scene of at least a third of the source's length (bands are learned from
   excerpts that long) on a different subject, from ink.js and the scene elements, with geometry you
   write, never traced; pass the pack's `palette.ink` as every ink.js call's `color` (the engine's
   own `INK` default is not the pack's). Render it at the source's size with `${CLAUDE_PLUGIN_ROOT}/scripts/render.py <scene.js> <frames dir>
   --fps <the pack's knobs.frame_rate.base_fps> --encode mp4 --playwright-core '${user_config.playwright_core}'` (it serves the scene's folder and `scripts/`), and run `inkstats.py <frames dir>.mp4 --cuts <shot starts>
   --pack <pack dir>`. It exits 0 only when every checked row and the palette pass. Each row prints
   its distance to source: 0 is the source value, 1 the band edge on either side. The film's
   distance ranks passing scenes and its margin names the row nearest failing.
6. Review: measure each prop with `--region X,Y,W,H --t T0-T1` next to source prop boxes, then
   read every drawing at 1:1 (tile frames so no image is over the 2576 px long edge the rotoscope skill's
   `reference/method.md`, Reviewing images, records; never
   downscale, never a GIF) beside source crops. A pass on the numbers with a crop that does not
   read as the style is a fail; say which mark is wrong.
7. Record: put the parameters that passed into the pack's `brush` and the result into `STYLE.md`,
   including where the scene still falls short.

Repeat 5-7 until the check passes and the crops read as the style. Tune the scene against the
check, never the check against the scene. `inkstats.py` also measures any film with no pack
(`--json` for the full summary), which is how to compare two films.

## Gotchas

- A post filter must not be what passes the check. Blur, noise, stripes and dry-brush overlays move
  edge softness and the amount of gray inside the ink, so those rows are measured but not checked.
  `grain` and `period` are measured only: on the woodcut source they follow codec residue and the
  pixel grid, and a flat black through h264 lands in `grain`'s band. `flat` rejects texture laid
  over all the black, and `rough` and `offstep` do not move under blur, noise, stripes or dry brush
  at all. `controls.py selftest <pack dir> [--near <film>]` exits 1 if the review's blur-and-stripes
  filter (and, with `--near`, the warped, retimed `ATTACK`) gets a synthetic or near-miss film
  through; rerun it with `--near` after changing a statistic.
- `straight` and `sliver` follow the subject, so they are checked only inside the content classes
  `border` and `caption` (`straight_border`, `sliver_caption`, ...) and printed as measured only over
  the whole frame. `boil` is measured on the border and caption. A scene without a frame line or a
  caption panel in the top quarter leaves those rows n/a; draw both, as the source does.
- Bands are learned per excerpt of the whole source, not per shot, so a very short film is judged
  against bands that may not fit it; there is no per-shot row.
- `w50` and `pw50` come from a distance transform and move in 2 px steps; every woodcut source
  excerpt has `pw50` 8, which is why neither is checked.
- A strictly regular timing fails `offstep`: hold a few drawings for 2 or 4 frames.
- `soft` needs a soften pass after drawing, since a two-tone canvas render has almost no edge ramp.
  Chromium's `ctx.filter = 'blur()'` does nothing below a floor (the rotoscope skill's
  `reference/method.md`, Rendering, holds the dated record); soften in JS instead.
