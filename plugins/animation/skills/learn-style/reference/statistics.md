# Style statistics: what they measure, how bands are set, which ones separate styles

The bands, source values, widenings and pass rates live in the pack's `style.json` (`bands`, `ref`,
`heldout`); this page explains them and keeps the measurement records they came from. Every record
here comes from `inkstats.py`, `learn.py` and `controls.py` runs on 2026-09-24 over the shfred0
source (239 drawings, nine shots), its rotoscoped replica (encoded to mp4 the way `capture.mjs`
encodes a scene), round 3 (a hand-authored replica of the same shots that the user rejected), three
clips in other styles (a kevin_t_ngo spiral engraving, a kevin_t_ngo torn-paper collage, a BiosRiosz
anime duel), and synthetic flat-polygon films. Treat the bands as this pack's, not as laws: a new
pack gets its own from its own source.

**One subject.** The source is one 30 s clip about one subject (a writer, a library, a city). Every
band, every held-out excerpt and the replica come from that subject, and round 3 replicates its
shots. So no result on this page is out-of-sample validation on a new subject: held-out here means
held out from the same clip. A scene on another subject is the first real test, and the
subject-sensitive rows below exist because the adjudication of such a scene found whole-frame
`straight` and `sliver` measuring what was drawn more than how.

## Contents

- The statistics
- Content classes
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
| `straight` | share of contour length in straight runs of 30 px or more: ruled lines and polygon edges; measured only | line, backgrounds |
| `straight_border`, `straight_caption` | the same over contour segments whose midpoint lies in that content class, leaving out runs along the frame edge: how straight the hand draws the frame and the caption panel | line |
| `specks`, `gaps` | ink and paper islands of 2-200 px per megapixel | texture |
| `holes` | paper share inside the ink after a 7 px closing: streaks and gouges in masses | texture |
| `ink_sd`, `paper_sd` | gray standard deviation inside eroded ink and paper: how much texture | texture |
| `field_sd` | the same inside the largest connected ink area only | texture, backgrounds |
| `flat` | dark drawings only (ink 50% or more): share of mostly-ink 32 px blocks that lie fully inside eroded ink with gray sd under 2: solid black against textured black | texture, backgrounds |
| `grain` | inside the ink interior, sd of the 5x5 box-mean gray over sd of the gray: the scale of the texture (near 1 for patches wider than 5 px, near 0.2 for pixel noise, lower for 1-2 px stripes) | texture |
| `sliver` | median area / width² of the paper islands inside the ink (carved slivers and gouges): long thin lines score high, chunky cuts low; measured only | texture, line |
| `sliver_border`, `sliver_caption` | the same over the islands centred in that content class: the breaks carved into the frame line, the counters and gaps of the lettering | texture, line |
| `period` | inside the eroded ink, the highest spatial power at periods under 32 px over the mean power there, divided by ln(eroded ink pixels): large for a texture at one fixed pitch (ruled stripes, a combed dry brush) | texture |
| `ink` | ink coverage | color |
| `boil` | over the border and caption classes (the anchor), on pairs whose anchor ink share changes under 1 point with 500 or more anchor edge pixels: ink/paper disagreement per anchor edge pixel, the mean edge displacement of the frame and caption between two drawings | line, movement |
| holds | each drawing's duration in 24 fps frames, on 1s/2s/3s/4+; drawings per second | frame rate |
| `offstep` | share of consecutive drawing pairs whose two holds do not add up to twice the most common hold: 0 on strict 3s; a drawing that re-timing to 24 fps moves one frame (a 2 then a 4) does not count | frame rate |

`--region X,Y,W,H --t T0-T1` measures one box over a time window (a box outside the frame is an
error), `--cuts` makes each shot a column of the table, and `--pack` prints each checked row with its
distance, and exits 1 on any failing row.

**Undefined is n/a.** A statistic with nothing to measure is n/a, never 0: `flat` with no dark
drawings, `boil` with no held pairs, `grain` and `period` with no ink interior, `rough` and
`straight` with no contour over 50 px, and so on. An n/a row neither passes nor fails, the distance
averages only the defined rows, and a film with no defined row exits 1.

## Content classes

`straight` and `sliver` follow the subject. Across the nine source shots whole-frame `straight`
runs 0.36-0.69 (bookshelves and windows high) and `sliver` 2.0-4.07 (glints and lit windows set it).
A scene on another subject would be judged on what it draws. So both are gated only inside content
classes every film of the style has, and reported, unjudged, over the whole frame
(`measured_only` in `style.json`; `inkstats.py --pack` prints them beside the source value).

`inkstats.py` assigns each pixel a class from the ink mask alone, by the same rule for the source
and for any film; nothing is declared by the scene:

| Class | Rule | Source |
|---|---|---|
| `border` | the ring within 2% of the frame's short side of its edge (`inkstats.BORDER`) | every drawing |
| `caption` | a paper rectangle in the top quarter, sealed by a 5 px closing of the ink, not touching the frame edge, 0.2-6% of the frame, at least 1.5x as wide as tall, filling 80% of its rotated box, holding ink; its box grown by the border width | detected in 7 of 9 shots, not on every drawing of them (a boiling outline can break the seal) |
| interior | everything else: the subject | never gated |

A class row joins `check` only when the source defines it in at least two of its parts
(`learn.py`), so a class seen in one shot cannot give a band. Per shot, `straight_border` runs
0.83-0.86 against whole-frame 0.36-0.69, and the anchored `boil` 1.14-1.54. `sliver_border` stays
noisy (2.5-4.7 per shot; about 9 islands per drawing), and the caption rows are wide. The interior
is never gated: by definition it is the subject, and a validation scene draws a different one.

`period` is area-normalized. Its peak-to-mean ratio for an irregular texture is the largest of about
as many independent spectral bins as the ink core has pixels, so it grows as the log of the ink
area. Dividing by ln(core pixels) takes that out: on the source's drawings the log-log slope of
`period` against core area drops from 0.09 to 0.015. A texture at one fixed pitch still grows with
area (slope 1.3 for round 3 with stripes), so the ratio stays large for it. Dividing by the area
itself over-corrects and widened the source's per-shot spread.

`boil` is anchored on the border and caption: the frame and the caption panel hold still in every
film of the style, so their boil does not depend on how the subject moves or how much carving it
has. The held test is the anchor's own ink share, not a whole-frame shift.

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
evaluation pass rates.

The palette tolerance (`palette.tolerance`) adds two measured terms and rounds up.
`palette.encode_shift` is the largest channel change in the clip's median ink or paper colour when
all its drawings are encoded as `capture.mjs` encodes a scene and decoded again. `palette.excerpt_stray`
is the largest channel difference between an excerpt's median colour and the clip's. Encoding moves
the woodcut ink by 4 levels on its blue channel (15 to 11), which is also what it does to the replica.

There are no per-shot rows. A shot of a few drawings (shfred0's 0.5 s flash has 3) cannot give a
stable median, and the per-shot rows needed a drawing-count exemption to pass the source itself. The
per-shot columns in the table are for reading, not for the check.

## Which statistics separate

`learn.py` `CHECK` holds twelve statistics; `style.json` `check` lists the ones the source defines
in at least two parts (all twelve for this pack), and `measured_only` the whole-frame `straight` and
`sliver`. Source excerpt ranges and bands are in `style.json` `heldout.rule` and `bands`. Round 3
values for the class rows, `period` and `boil` exist only for round 3 through game.py's filter (the
one near-miss film this worktree holds); see "The control suite".

| Stat | Replica | Round 3 | What it rejects |
|---|---|---|---|
| `straight_border` | 0.832 | 0.896 with game.py's filter | a frame ruled too straight: round 3's, flat polygons (0.995) |
| `straight_caption`, `sliver_border`, `sliver_caption` | 0.476, 4.00, 2.50 | 0.463, 4.02, 1.92 with game.py's filter | nothing measured yet; gated because the source has the class |
| `rough` | 0.069 | 0.053-0.056 | round 3 and every filter of it, flat polygons (0.025), the spiral and anime clips |
| `offstep` | 0.101 | 0.004 (on strict 3s) | round 3, the anime and collage clips |
| `grain` | 0.689 | 0.44 raw; 0.21-0.32 with noise, 0.48-0.57 with stripes, 0.64 with dry brush, 0.54 at blur 0.6, 0.79 at blur 1.3 | pixel noise, stripes, flat fills made gray by a blur |
| `period` | 45.4 | 12319 with game.py's filter | fixed-pitch texture, pixel noise |
| `flat` | 0.537 | 0 with any overlay over all the black | textures laid over every black area |
| `boil` | 1.44 | 1.04 with game.py's filter | flat polygons (1.79, vertex boil), round 3 through game.py's filter |
| `holes`, `per_second` | pass | pass | flat polygons, the other styles, a noise that changes every frame |

`rough` and `offstep` are drawing and timing structure: a blur, noise, stripe or dry-brush overlay
leaves them where they were (round 3 stays at 0.054 and 0.004 through every such filter).
Whole-frame `straight` (round 3 0.687-0.696 against the source excerpts' 0.51-0.64) and `sliver`
(3.50-3.75 against 2.19-3.36) separated round 3 too, but only because round 3 draws the same
subject; they are measured only now.

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

The content-class change was checked on 2026-09-24 against a partial suite. Round 3 and the other
styles' clips were not re-measured in this run (their films sit outside this worktree, and access was
not granted), so those controls are judged on their earlier summaries with `period` and `boil`
removed (the two statistics whose definition changed): only the rows whose measurement did not change
(`rough`, `offstep`, `grain`, `flat`, `holes`, `per_second`, palette) can reject them, and the new
class rows are n/a for them. Everything this worktree holds was re-measured: the polygon family,
round 3 through game.py's filter, the source's drawings encoded as `capture.mjs` encodes a scene, and
the replica.

| Half | Control | Measured | Rows failed | Margin | Worst row |
|---|---|---|---|---|---|
| calibration | polygons, blur 0.9 + noise 8 | now | 8/11 | +23.19 | grain |
| calibration | polygons, blur 0.9 + stripes 12 | now | 7/11 | +1028.39 | period |
| calibration | polygons | now | 8/11 | +16.62 | grain |
| calibration | polygons, warp 3 + blur 0.9 + noise 8 | now | 9/12 | +46.38 | straight_border |
| evaluation | round 3, blur 0.9 + stripes 12 (the review's game.py) | now | 7/14 | +1082.78 | period |
| evaluation | polygons, blur 0.9 + dry 16 | now | 8/11 | +11.72 | straight_border |
| evaluation | polygons, blur 0.9 | now | 8/11 | +11.54 | straight_border |
| evaluation | polygons, noise 8 then blur 0.9 | now | 8/11 | +11.57 | straight_border |
| calibration | anime (BiosRiosz) | earlier | 7/8 | +119.35 | per_second |
| calibration | spiral | earlier | 4/7 | +12.60 | ink_rgb |
| calibration | round 3, blur 0.6 | earlier | 3/8 | +6.88 | grain |
| calibration | round 3, blur 0.9 + dry 32 | earlier | 5/8 | +5.40 | ink_rgb |
| calibration | round 3, blur 0.9 + dry 8 | earlier | 5/8 | +1.58 | grain |
| calibration | round 3, blur 0.9 + noise 16 | earlier | 5/8 | +131.79 | per_second |
| calibration | round 3, blur 0.9 + noise 4 | earlier | 4/8 | +17.91 | grain |
| calibration | round 3, blur 0.9 + noise 8 + stripes 12 + dry 16 | earlier | 5/8 | +10.69 | grain |
| calibration | round 3, blur 0.9 + stripes 6 | earlier | 3/8 | +5.39 | grain |
| calibration | round 3 | earlier | 3/8 | +11.96 | grain |
| calibration | round 3, stripes 12 | earlier | 3/8 | +9.97 | grain |
| calibration | round 3, attack with warp 0.4 | earlier | 0/8 | -0.02 | rough |
| calibration | round 3, attack (`ATTACK`, warp 0.5) | earlier | 0/8 | -0.21 | rough |
| calibration | round 3, warp 1.5 + blur 0.9 | earlier | 2/8 | +0.88 | rough |
| evaluation | collage | earlier | 6/8 | +45.97 | per_second |
| evaluation | round 3, blur 0.9 + dry 16 | earlier | 5/8 | +2.20 | ink_rgb |
| evaluation | round 3, blur 0.9 + dry 16 on the left half | earlier | 3/8 | +4.93 | grain |
| evaluation | round 3, blur 0.9 + noise 8 | earlier | 4/8 | +21.94 | grain |
| evaluation | round 3, blur 0.9 + stripes 24 | earlier | 3/8 | +8.98 | grain |
| evaluation | round 3, blur 0.9 | earlier | 3/8 | +0.47 | offstep |
| evaluation | round 3, blur 1.3 | earlier | 3/8 | +3.44 | grain |
| evaluation | round 3, noise 8 then blur 0.9 | earlier | 4/8 | +5.28 | grain |
| evaluation | round 3, attack without blur (warp 0.5, rows 0.2, noise 0.6) | earlier | 1/8 | +9.77 | grain |
| evaluation | round 3, attack with warp 0.7 | earlier | 0/8 | -0.56 | holes |
| evaluation | round 3, warp 0.7 + blur 0.9 | earlier | 1/8 | +0.47 | offstep |
| evaluation | round 3, warp 3 + blur 0.9 | earlier | 2/8 | +3.25 | rough |

Every re-measured control fails, and every control judged on its earlier summary fails except the
three attack films. The attack (`controls.py` `ATTACK`) is game.py plus three more filters: a static
0.5 px contour warp (moves `straight` and `rough` into their bands), one frame held longer every
3 s (`offstep`), and faint tonal rows 20-40 px apart with fine noise (`period`, `grain`). The only
row that rejected it was whole-frame `sliver` (+0.14 to +0.23), now measured only. Whether
`straight_border`, `sliver_border`, the anchored `boil` or the normalized `period` reject it is
**unverified**: rerun `controls.py measure` with round 3 as `--near` and `controls.py selftest
<pack dir> --near <round 3>`. `controls.py selftest` without `--near` (game.py's filter on
synthetic polygons) exits 0: it fails `straight_border`, `rough`, `offstep`, `grain`, `period`,
`holes`, `boil` and `per_second`.

## Held-out and out-of-sample results

- Held-out source excerpts: 150/150 calibration and 150/150 evaluation pass every checked row, and
  each band passes 150/150 in both halves.
- Held out within the clip: the evaluation controls set no band; the re-measured ones fail, and the
  three attack films are unverified (above). The evaluation excerpts set no band, and all 150 pass.
  None of this is out-of-sample validation: it is the same subject (see "One subject").
- Replica (its decoded mp4, judged as the source is): 0/14 rows fail, margin -0.20; the source's
  drawings encoded the same way also pass at -0.20. The closest row for both is the palette (ink 4
  levels off against a tolerance of 5).

Five choices were made after seeing evaluation or positive results, so their results are **not out of
sample**:

| Choice | Seen first |
|---|---|
| `ink_sd` left `CHECK` | an evaluation excerpt failed it |
| `offstep` changed to the pair form | an evaluation excerpt and the replica (0.23) failed the per-drawing form |
| the cap counts each control only at its strongest row | an evaluation excerpt failed under the per-row cap |
| `sliver` added to `CHECK` | chosen to catch the attack, after it passed |
| content classes, the `period` normalization and the anchored `boil` | proposed by the adjudication of a scene on another subject; the 2% border width was picked from per-shot source values, not from any control |

Every other choice was made on calibration data.

## Distance to source

A row's distance is |film value - source value| divided by |band edge - source value|, taking the
band edge on the film's side of the source value. It is 0 at the source value and 1 at either band
edge, however asymmetric the band. A row fails above 1. The film's distance is the mean over its
defined rows and ranks films that pass; its margin (largest row distance minus 1) says how far the
worst row is from the edge. The source scores 0.

## What the check cannot say

- **The attack is unverified.** Whole-frame `sliver`, the one row that caught it, is measured only
  now, and round 3 has not been re-measured with the class rows (see "The control suite").
- **A film with no border or caption skips their rows.** A class the film lacks is n/a, neither
  pass nor fail, so a scene drawn without a frame line or caption panel is judged on the other rows
  only. The caption detector also misses panels whose boiling outline breaks its seal, and it looks
  only in the top quarter, where the source puts them.
- **Subject still leaks into the interior rows.** `grain`, `period`, `flat` and `holes` are measured
  over the whole ink, which is mostly the subject; only `straight`, `sliver` and `boil` moved to
  classes.
- **Composition and reading.** It checks mechanics, not whether a scene reads as the style. The
  research slice on style learning found no agreed metric or ground truth for style similarity, so
  human judgment on 1:1 crops stays the final gate.
- **Short films.** Bands come from excerpts of at least a third of the source (about 10 s); a
  shorter film is judged against bands it may not fit.
