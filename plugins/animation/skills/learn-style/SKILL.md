---
description: "Learn a drawn animation style from a rotoscoped clip into a style pack: measure its traces and source drawings into knob values and statistic bands (edge softness, stroke and gap widths, edge roughness, gray inside the ink, boil between held drawings, holds on 1s/2s/3s, palette), then prove the pack by authoring a new scene with ink.js and checking its render against it. Use when: 'learn this style', 'make a style pack', 'extract the style from this clip', 'does my film match the style', 'check this scene against the woodcut pack', 'which statistics separate styles'. Needs a rotoscope work dir; not for copying a clip one to one."
argument-hint: "<rotoscope work dir> <pack dir>"
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
band is set, and which statistics separated the woodcut style from a near miss and from three
other styles.

Requirements: the rotoscope skill's requirements (Python with numpy and opencv through
`uv run --with numpy,opencv-python-headless python ...`, `ffmpeg`, `ffprobe`, Node and
playwright-core with Chromium) and a rotoscope work directory (`d/dNNN.json` traces and
`src/dNNN.png` drawings). The scripts are `${CLAUDE_PLUGIN_ROOT}/skills/learn-style/scripts/learn.py`
and the shared `${CLAUDE_PLUGIN_ROOT}/scripts/inkstats.py`.

## Pack format

`styles/<name>/` in the plugin, tool-neutral:

| File | Written by | Holds |
|---|---|---|
| `style.json` | `learn.py`, then you | `palette` (ink, paper, tone ramp), `knobs` (the seven-knob schema), `stats` (p10/p50/p90), `timing`, `bands`, `check`, `brush`, `credit`, `rotoscope_fits` |
| `STYLE.md` | you | the style in words for a reader: credit, knob table with each value marked measured or judgment, how to author in it, the validation result |

`learn.py` measures `palette`, `stats`, `timing`, `bands` and the `color`, `line`, `frame_rate`
and `texture` knobs. Bands come from held-out validation over the source's segments, not from a
chosen margin; `heldout` records the widening each statistic needed. It keeps what it cannot measure from an existing `style.json`: `credit`,
`brush`, `check`, and the `movement`, `camera` and `backgrounds` knobs, which you fill from
viewing the source and mark `"basis": "judgment"`. A re-run refreshes numbers without losing them.

## Loop

1. Learn: `learn.py <work> <pack dir> --credit "<who made the source, its URL, date>" --negative
   <inkstats --json of near misses and other styles>`. The negatives cap each band's widening so
   they keep failing; without them bands get full held-out coverage.
2. Describe: fill the judgment knobs in `style.json` and write `STYLE.md`.
3. Validate: author a short scene (about 10 s) on a subject different from the source, from
   ink.js and the scene elements, with geometry you write, never traced. Start from the pack's
   `brush`; a new pack starts from the woodcut-ink one. Render it at the source's size with
   `capture.mjs --fps 24`, encode with the ffmpeg line at the top of `capture.mjs`, and run
   `inkstats.py <scene.mp4> --cuts <shot starts> --pack <pack dir>`. It exits 0 only when every
   checked statistic, every shot's dark field and the palette pass. Passing is not centring: it
   also prints the distance to source (0 is the source, 1 a band edge on average), which ranks
   passing scenes; read the per-shot columns so no shot hides behind the median.
4. Review: measure each prop with `--region X,Y,W,H --t T0-T1` next to source prop boxes, then
   read every drawing at 1:1 (tile frames so no image is over 2576 px on the long edge; never
   downscale, never a GIF) beside source crops. A pass on the numbers with a crop that does not
   read as the style is a fail; say which mark is wrong.
5. Record: put the parameters that passed into the pack's `brush` and the result into `STYLE.md`,
   including where the scene still falls short.

Repeat 3-5 until the check passes and the crops read as the style. `inkstats.py` also measures
any film with no pack (`--json` for the full summary), which is how to compare two films.

## Gotchas

- Boil is edge displacement per edge pixel, so a thin stroke that jumps wholesale (rain, hairlines)
  holds it near its own width, and vertex jitter barely moves it. What raised the validation
  scene from 1.5 to 2.6 px was sliding each stroke's ends (18 px) and shifting whole strokes
  sideways (5.5 px) every drawing, the way a hand redraws.
- Ridge widths come from a distance transform, so `w50` and `pw50` move in steps (4, 5, 6 px); a
  value on a band edge flips with a small change. Aim for the middle of the band.
- Large solid ink areas push `w50` up and thin gouges pull `pw50` down. The woodcut source keeps
  black regions narrow by carving them: gouges about 9.5 px wide every 24 px brought the
  validation scene to `w50` 16 and `pw50` 8, the source's own values.
- A filled polygon prop measures wrong at the region level: too straight, no gray. Stroke-built
  props (overlapping fill strokes, edges re-stroked past the corners) land inside the source's
  prop range.
- `soft` needs a soften pass after drawing: a two-tone canvas render has almost no ramp (round 3:
  0.94 px against the source's 2.54). A JS gaussian of sigma 0.92 gives 2.46; Chromium's
  `ctx.filter = 'blur()'` does nothing below about 0.8 px (measured 2026-09-24 on Playwright's
  Chromium build 1246; recheck when that build changes).
- `ink_sd` and `flat` pull against each other: gray inside the ink needs dry-brush texture, but
  about half the woodcut source's dark area is flat black. Texture a band of each dark field and
  leave the rest flat; carving a field everywhere drove `flat` to 0 and failed the check. Keep the
  drag at gray 32 or darker: a drag lighter than ink + 16 counts as edge ramp and pushes `soft`
  up (a `#312c28` drag gave `soft` 3.5), and it widens small props' edge ramp most.
- Widening every band by its largest held-out miss lets near misses pass. Pass `--negative`
  controls so the widening stops short of them, and judge the check by a same-style control no
  band saw (the rotoscope replica) passing and those controls failing.
