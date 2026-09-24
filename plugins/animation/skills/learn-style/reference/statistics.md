# Style statistics: what they measure, how bands are set, which ones separate styles

The bands, source values, widenings and pass rates live in the pack's `style.json` (`bands`, `ref`,
`heldout`); this page explains them and keeps the measurement records they came from. Every record
here comes from `inkstats.py`, `learn.py` and `controls.py` runs on 2026-09-24 over the shfred0
source (239 drawings, nine shots), its rotoscoped replica (encoded to mp4 the way `capture.mjs`
encodes a scene), round 3 (a hand-authored replica of the same shots that the user rejected), three
clips in other styles (a kevin_t_ngo spiral engraving, a kevin_t_ngo torn-paper collage, a BiosRiosz
anime duel), and synthetic flat-polygon films. Treat the bands as this pack's, not as laws: a new
pack gets its own from its own source.

## Contents

- The statistics
- How a band is set
- Which statistics separate
- The control suite
- Held-out and out-of-sample results
- Distance to source
- What the check cannot say

## The statistics

Per drawing, with ink and paper at the gray histogram modes and T at their midpoint:

| Stat | Measures | Knob |
|---|---|---|
| `soft` | mid-gray pixels per ink edge pixel: the edge ramp width in px (blur, anti-aliasing, soft brush) | texture |
| `w10` `w50` `w90` | ink stroke width, 2x the distance transform on its ridge | line |
| `pw50` | paper width median: the cream gaps, gouges and slivers between strokes | line, texture |
| `rough` | raw contour length over its 4 px polygon approximation, minus 1: edge wobble | line |
| `straight` | share of contour length in straight runs of 30 px or more: ruled lines and polygon edges | line, backgrounds |
| `specks`, `gaps` | ink and paper islands of 2-200 px per megapixel | texture |
| `holes` | paper share inside the ink after a 7 px closing: streaks and gouges in masses | texture |
| `ink_sd`, `paper_sd` | gray standard deviation inside eroded ink and paper: how much texture | texture |
| `field_sd` | the same inside the largest connected ink area only | texture, backgrounds |
| `flat` | dark drawings only (ink 50% or more): share of mostly-ink 32 px blocks that lie fully inside eroded ink with gray sd under 2: solid black against textured black | texture, backgrounds |
| `grain` | inside the ink interior, sd of the 5x5 box-mean gray over sd of the gray: the scale of the texture (near 1 for patches wider than 5 px, near 0.2 for pixel noise, lower for 1-2 px stripes) | texture |
| `period` | inside the eroded ink, the highest spatial power at periods under 32 px over the mean power there: large for a texture at one fixed pitch (ruled stripes, a combed dry brush) | texture |
| `ink` | ink coverage | color |
| `boil` | on held pairs (shift under 1 px, ink change under 1 point), ink/paper disagreement per edge pixel: mean edge displacement between two drawings of one pose | line, movement |
| holds | each drawing's duration in 24 fps frames, on 1s/2s/3s/4+; drawings per second | frame rate |
| `offstep` | share of consecutive drawing pairs whose two holds do not add up to twice the most common hold: 0 on strict 3s; a drawing that re-timing to 24 fps moves one frame (a 2 then a 4) does not count | frame rate |

`--region X,Y,W,H --t T0-T1` measures one box over a time window (a box outside the frame is an
error), `--cuts` makes each shot a column of the table, and `--pack` prints each checked row with its
distance, and exits 1 on any failing row.

**Undefined is n/a.** A statistic with nothing to measure is n/a, never 0: `flat` with no dark
drawings, `boil` with no held pairs, `grain` and `period` with no ink interior, `rough` and
`straight` with no contour over 50 px, and so on. An n/a row neither passes nor fails, the distance
averages only the defined rows, and a film with no defined row exits 1.

## How a band is set

The check judges a whole film, so `learn.py` learns bands from film-sized excerpts of the source,
never from single shots or fixed segments. It cuts the source at its shots (`--cuts`). An excerpt is
a set of shots holding a third to two thirds of the duration, paired with its complement. A third of
30 s is about 10 s, the length SKILL.md asks a validation scene to be. On the nine shfred0 shots
that gives 150 pairs: every split by shot, in both directions. Alternate pairs form a calibration
half, which sets the bands, and an evaluation half, which only tests them.

For each statistic, the raw band spans the calibration excerpts' values (and the whole source's).
It is widened, in the statistic's own units, by the largest miss of one calibration pair against the
band of the others. The widening is capped at `CLEAR` (0.5) times the smallest distance by which a
calibration control lies outside the raw band. Each control counts only at the checked row that
rejects it most, so that row keeps rejecting it by a clear margin while the other rows keep full
held-out coverage. `style.json` `heldout.rule` records, per statistic, the raw band, the held-out
miss, the widening, the controls that cap it, every control's margin, and the calibration and
evaluation pass rates. The palette tolerance is the largest channel difference between a shot's
median ink or paper colour and the clip's.

There are no per-shot rows. A shot of a few drawings (shfred0's 0.5 s flash has 3) cannot give a
stable median, and the per-shot rows needed a drawing-count exemption to pass the source itself. The
per-shot columns in the table are for reading, not for the check.

## Which statistics separate

`learn.py` `CHECK` holds nine statistics. Values are film values from the records above; the
source's excerpt ranges are the raw bands in `style.json` `heldout.rule`.

| Stat | Source excerpts | Replica | Round 3, every post filter | What it rejects |
|---|---|---|---|---|
| `straight` | 0.51-0.64 | 0.544 | 0.687-0.696 | round 3 and every filter of it, flat polygons (0.98) |
| `rough` | 0.059-0.076 | 0.069 | 0.053-0.056 | round 3 and every filter of it, flat polygons (0.025), the spiral and anime clips |
| `offstep` | 0.031-0.141 | 0.101 | 0.004 (on strict 3s) | round 3, the anime and collage clips |
| `grain` | 0.674-0.715 | 0.689 | 0.44 raw; 0.21-0.32 with noise, 0.48-0.57 with stripes, 0.64 with dry brush, 0.54 at blur 0.6, 0.79 at blur 1.3 | pixel noise, stripes, flat fills made gray by a blur |
| `period` | 537-886 | 592 | 74 raw; 1.1e5-1.9e5 with stripes; 15-81 with noise | fixed-pitch texture, pixel noise |
| `flat` | 0.13-0.80 | 0.537 | 0 with any overlay over all the black | textures laid over every black area |
| `holes`, `boil`, `per_second` | see `style.json` | pass | pass | flat polygons, the other styles, a noise that changes every frame |

`straight`, `rough` and `offstep` are drawing and timing structure: a blur, noise, stripe or
dry-brush overlay leaves them where they were (round 3 stays at 0.69, 0.054 and 0.004 through every
such filter). Under every such filter round 3 fails all three, at distances of 1.29 to 1.57.
Blur, noise and stripes set the old texture rows (`soft`, `ink_sd`, `field_sd`), so those rows no
longer separate anything. They stay measured, unchecked. `soft` would also reject the replica: 2.36
against the source excerpts' 2.51-2.66. `w50` and `pw50` move in 2 px steps (every source excerpt has
`pw50` 8), and `ink`, `w10`, `specks` and `gaps` follow the subject. Coherence of boil across a
drawing (per-tile displacement spread) did not separate round 3 (0.94 against the source's 0.92),
and was dropped.

## The control suite

`controls.py measure` builds every control and `controls.py check` reruns the verdicts. Controls
alternate between halves within each family: `near` (round 3 through every filter), `poly`
(synthetic flat polygons with vertex boil and the source's hold mix), and the other styles. Only the
calibration half is passed to `learn.py --negative`. Margin is the largest row distance minus 1: a
control needs a margin above 0.

| Half | Control | Rows failed | Margin | Worst row |
|---|---|---|---|---|
| calibration | anime (BiosRiosz) | 10/11 | +119.35 | per_second |
| calibration | spiral | 7/10 | +16.00 | ink_rgb |
| calibration | round 3, blur 0.6 | 5/11 | +6.88 | grain |
| calibration | round 3, blur 0.9 + dry 32 | 7/11 | +7.00 | ink_rgb |
| calibration | round 3, blur 0.9 + dry 8 | 7/11 | +1.58 | grain |
| calibration | round 3, blur 0.9 + noise 16 | 8/11 | +131.79 | per_second |
| calibration | round 3, blur 0.9 + noise 4 | 6/11 | +17.91 | grain |
| calibration | round 3, blur 0.9 + noise 8 + stripes 12 + dry 16 | 7/11 | +126.74 | period |
| calibration | round 3, blur 0.9 + stripes 6 | 5/11 | +630.87 | period |
| calibration | round 3 | 5/11 | +11.96 | grain |
| calibration | round 3, stripes 12 | 5/11 | +904.71 | period |
| calibration | round 3, warp 1.5 + blur 0.9 | 4/11 | +6.84 | straight |
| calibration | polygons, blur 0.9 + noise 8 | 8/11 | +23.19 | grain |
| calibration | polygons, blur 0.9 + stripes 12 | 7/11 | +884.36 | period |
| calibration | polygons | 8/11 | +16.62 | grain |
| calibration | polygons, warp 3 + blur 0.9 + noise 8 | 8/11 | +23.32 | grain |
| evaluation | collage | 9/11 | +45.97 | per_second |
| evaluation | round 3, blur 0.9 + dry 16 | 7/11 | +3.00 | ink_rgb |
| evaluation | round 3, blur 0.9 + dry 16 on the left half | 4/11 | +4.93 | grain |
| evaluation | round 3, blur 0.9 + noise 8 | 6/11 | +21.94 | grain |
| evaluation | round 3, blur 0.9 + stripes 12 (the review's game.py) | 5/11 | +940.44 | period |
| evaluation | round 3, blur 0.9 + stripes 24 | 5/11 | +1073.33 | period |
| evaluation | round 3, blur 0.9 | 5/11 | +1.34 | period |
| evaluation | round 3, blur 1.3 | 4/11 | +3.44 | grain |
| evaluation | round 3, noise 8 then blur 0.9 | 6/11 | +5.28 | grain |
| evaluation | round 3, warp 3 + blur 0.9 | 4/11 | +11.21 | straight |
| evaluation | round 3, warp 0.7 + blur 0.9 | 2/11 | +1.01 | period |
| evaluation | polygons, blur 0.9 + dry 16 | 8/11 | +3.32 | straight |
| evaluation | polygons, blur 0.9 | 8/11 | +3.32 | straight |
| evaluation | polygons, noise 8 then blur 0.9 | 8/11 | +7.03 | grain |

All 30 controls fail. `controls.py selftest` reruns the review's game.py filter on synthetic polygons
(and on round 3 when given) and exits 1 if the gamed film passes.

## Held-out and out-of-sample results

- Held-out source excerpts: 150/150 calibration and 150/150 evaluation pass every checked row, and
  each band passes 150/150 in both halves.
- Out of sample: the evaluation controls set no band, and all 14 fail. The evaluation excerpts set no
  band, and all 150 pass.
- Replica: 0/11 rows fail. Its closest row is the palette: its ink is 4 levels from the pack's ink,
  exactly the tolerance.
- The out-of-sample claim has two caveats. `ink_sd` left the check, and `offstep` changed from the
  share of drawings off the common hold to the pair form, after an evaluation excerpt failed each
  and after the replica failed the old `offstep` at 0.23. The cap now counts each control only at
  its strongest row, a change made after the same result. Every other choice was made on
  calibration data.

## Distance to source

A row's distance is |film value - source value| divided by |band edge - source value|, taking the
band edge on the film's side of the source value. It is 0 at the source value and 1 at either band
edge, however asymmetric the band. A row fails above 1. The film's distance is the mean over its
defined rows and ranks films that pass; its margin (largest row distance minus 1) says how far the
worst row is from the edge. The source scores 0 and the replica 0.193.

## What the check cannot say

- **A fine contour warp plus a retime.** A static 0.4-0.7 px displacement warp before the blur moves
  round 3's `straight` (0.51-0.63) and `rough` (0.059-0.066) inside their bands. Round 3 is then
  caught only by `offstep`, which an author fixes by re-timing a few drawings, and by `period`,
  which a texture at the source's power could set. A near miss that does all three was not built
  and would likely pass.
- **Composition and reading.** It checks mechanics, not whether a scene reads as the style. The
  research slice on style learning found no agreed metric or ground truth for style similarity, so
  human judgment on 1:1 crops stays the final gate.
- **Short films.** Bands come from excerpts of at least a third of the source (about 10 s); a
  shorter film is judged against bands it may not fit.
