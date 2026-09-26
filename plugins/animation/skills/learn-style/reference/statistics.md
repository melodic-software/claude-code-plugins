# Style statistics: what they measure, how bands are set, which ones separate styles

The bands, source values, widenings and pass rates live in the pack's `style.json` (`bands`, `ref`,
`heldout`); this page explains them and keeps the measurement records they came from. Every record
here comes from `inkstats.py`, `learn.py` and `controls.py` runs on 2026-09-24 over the shfred0
source (239 drawings, nine shots), its rotoscoped replica (encoded to mp4 the way `render.py`
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
| `grain` | inside the ink interior, sd of the 5x5 box-mean gray over sd of the gray: the scale of the texture (near 1 for patches wider than 5 px, near 0.2 for pixel noise, lower for 1-2 px stripes); measured only (see "Second adjudication") | texture |
| `sliver` | median area / width² of the paper islands inside the ink (carved slivers and gouges): long thin lines score high, chunky cuts low; measured only | texture, line |
| `sliver_border`, `sliver_caption` | the same over the islands centred in that content class: the breaks carved into the frame line, the counters and gaps of the lettering | texture, line |
| `period` | inside the eroded ink, at periods under 32 px, the largest ratio of one spectral bin's power to the mean power of every bin at the same frequency, divided by ln(eroded ink pixels): large for a texture at one fixed pitch and direction (ruled stripes, a combed dry brush), near the noise level for irregular texture and smooth tone drift | texture |
| `ink` | ink coverage | color |
| `boil` | over the border and caption classes (the anchor), on pairs whose anchor ink share changes under 1 point with 500 or more anchor edge pixels: ink/paper disagreement per anchor edge pixel, the mean edge displacement of the frame and caption between two drawings | line, movement |
| holds | each drawing's duration in frames at the pack's base rate (`knobs.frame_rate.base_fps`), on 1s/2s/3s/4+; drawings per second | frame rate |
| `offstep` | share of consecutive drawing pairs whose two holds do not add up to twice the most common hold: 0 on strict 3s; a drawing that re-timing to 24 fps moves one frame (a 2 then a 4) does not count | frame rate |

`--region X,Y,W,H --t T0-T1` measures one box over a time window (a box outside the frame is an
error), `--cuts` makes each shot a column of the table, and `--pack` prints each checked row with its
distance, and exits 1 on any failing row.

**Undefined is n/a.** A statistic with nothing to measure is n/a, never 0: `flat` with no dark
drawings, `boil` with no held pairs, `grain` and `period` with no ink interior, `rough` and
`straight` with no contour over 50 px, and so on. An n/a row neither passes nor fails, the distance
averages only the defined rows, and a film with no defined row exits 1. One exception: a
content-class row (`*_border`, `*_caption`, and `boil` on border or caption) that the film leaves
undefined although it has the class fails at distance inf. A frame ring that is 10% or more ink
(`inkstats.PRESENT`) in any drawing, or any detected caption panel, is the class; a frame with no
slivers, too little contour or no held anchor pairs is then a miss, not a free pass.

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
| `border` | the ring within 3% of the frame's short side of its edge (`inkstats.BORDER`, 29 px here), for every border row: the frame stroke and the paper margin outside it. Measured on the source (every drawing, each side with an inner edge, 445 sides): the stroke starts 9 px in (p95 10) and is 19 px wide (median), so it ends by 29 px. The other 511 sides run into a dark field | every drawing |
| `caption` | a paper rectangle in the top quarter, sealed by a 5 px closing of the ink, not touching the frame edge, 0.2-6% of the frame, at least 1.5x as wide as tall, filling 80% of its rotated box, holding ink; its box grown by 1.3% of the short side (`inkstats.CAPTION`, 13 px here) for every caption row: measured on the source (231 box sides with an outer edge), the outline starts at the paper edge and is 13 px wide (median) | detected in 7 of 9 shots, not on every drawing of them (a boiling outline can break the seal) |
| interior | everything else: the subject | never gated |

A class row joins `check` only when the source defines it in at least two of its parts
(`learn.py`), so a class seen in one shot cannot give a band. The caption rows are wide. The
interior is never gated: by definition it is the subject, and a validation scene draws a different
one.

`period` is area-normalized: the largest of many bin ratios grows as the log of the ink area, and
dividing by ln(core pixels) takes that out (with the earlier peak-to-mean form, the source's log-log
slope against core area dropped from 0.09 to 0.015). A texture at one fixed pitch still grows with
area, so the ratio stays large for it. Dividing by the area itself over-corrects.

`boil` is anchored on the border and caption: the frame and the caption panel hold still in every
film of the style, so their boil does not depend on how the subject moves or how much carving it
has. The held test is the anchor's own ink share, not a whole-frame shift.

## Second adjudication

An independent adjudication (2026-09-24, measured on the source with `inkstats.py` unmodified)
found four rows measuring something other than what they claim. Each was fixed or made measured
only; no band was widened.

| Row | Finding | Change |
|---|---|---|
| `grain` | The source's blacks are 99.5% within ±1 gray level deep inside; a few hundred stray pixels and codec residue set the ratio. A flat black encoded by h264 scored 0.713, inside the band | measured only: the source shows no visible ink texture for it to measure |
| `period` | The peak sat at the 32 px cutoff in every film: the tail of smooth tone drift, not a pitch. A flattened source still scored 38 | the peak is now a bin's power over the mean of all bins at the same frequency, at pitches of 3-24 px, so drift scores at the noise level (a flattened source plus 1 level of noise: 1.1). But the source's own peaks then lie exactly on the axes at 2-5 px pitch in every drawing sampled: the pixel grid and codec, and the straight edges of the eroded-ink mask, not a drawn texture. No band from them measures style, so `period` is measured only |
| `sliver_border`, `boil` | The 2% (20 px) ring let the subject in: 61% of the source's ring edge pixels 15-20 px in moved 4 px or more, against 8-11% within 10 px, and most border islands were subject nicks | `sliver_border` still needs 3 islands in a drawing. The border ring was then set once for all border rows from where the source's stroke lies (see "Content classes") |
| `rough` | the excess in the adjudicated film came from many small contours, a real drawing trait | unchanged and gated; its description now names small marks as well as edge wobble |

## How a band is set

The check judges a whole film, so `learn.py` learns bands from film-sized excerpts of the source,
never from single shots or fixed segments. It cuts the source at its shots (`--cuts`; without them, at
`--seg`-second segments, default `inkstats.py` `SEG`). An excerpt is
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
all its drawings are encoded as `render.py` encodes a scene and decoded again. `palette.excerpt_stray`
is the largest channel difference between an excerpt's median colour and the clip's. Encoding moves
the woodcut ink by 4 levels on its blue channel (15 to 11), which is also what it does to the replica.

There are no per-shot rows. A shot of a few drawings (shfred0's 0.5 s flash has 3) cannot give a
stable median, and the per-shot rows needed a drawing-count exemption to pass the source itself. The
per-shot columns in the table are for reading, not for the check.

## Which statistics separate

`learn.py` `CHECK` holds ten statistics; `style.json` `check` lists the ones the source defines
in at least two parts (all ten for this pack), and `measured_only` the whole-frame `straight` and
`sliver`, `grain` and `period`. Source excerpt ranges and bands are in `style.json` `heldout.rule` and `bands`.

| Stat | Replica | Round 3, every post filter | What it rejects |
|---|---|---|---|
| `straight_border` | 0.832 | 0.895-0.901 without a warp; 0.80-0.84 at warp 0.4-0.5, 0.70 at 0.7, 0.10-0.34 at 1.5-3 | a frame ruled too straight or bent by a warp: round 3's, flat polygons (0.995) |
| `straight_caption` | 0.476 | 0.46-0.47; 0.34-0.42 with a warp | the attack films (warp 0.4-0.7) |
| `sliver_border` | 3.53 | 1.49-1.88 | round 3's frame and every filter of it, flat polygons (none: inf) |
| `sliver_caption` | 2.50 | 1.67-2.25 | round 3's lettering under most filters, the attack films |
| `rough` | 0.069 | 0.053-0.056 | round 3 and every filter of it, flat polygons (0.025), the spiral and anime clips |
| `offstep` | 0.101 | 0.004 (on strict 3s) | round 3, the anime and collage clips |
| `grain` | 0.689 | 0.44 raw; 0.21-0.32 with noise, 0.48-0.57 with stripes, 0.64 with dry brush, 0.54 at blur 0.6, 0.79 at blur 1.3 | measured only (see "Second adjudication") |
| `period` | measured only | | measured only (see "Second adjudication") |
| `flat` | 0.537 | 0 with any overlay over all the black | textures laid over every black area |
| `boil` | 1.45 | 1.08-1.13 | round 3 and every filter of it (its frame barely boils), flat polygons (1.79, vertex boil) |
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

| Half | Control | Rows failed | Margin | Worst row |
|---|---|---|---|---|
| calibration | BiosRiosz-2102523343253520764 | 8/10 | +119.35 | per_second |
| calibration | kevin_t_ngo-2102171059592241410 | 7/9 | +12.60 | ink_rgb |
| calibration | near_blur0.6 | 6/12 | +4.73 | sliver_border |
| calibration | near_blur0.9+dry32 | 8/12 | +5.40 | ink_rgb |
| calibration | near_blur0.9+dry8 | 8/12 | +5.05 | sliver_border |
| calibration | near_blur0.9+noise16 | 8/12 | +131.79 | per_second |
| calibration | near_blur0.9+noise4 | 7/12 | +5.02 | sliver_border |
| calibration | near_blur0.9+noise8+stripes12+dry16 | 8/12 | +4.86 | sliver_border |
| calibration | near_blur0.9+stripes6 | 6/12 | +5.02 | sliver_border |
| calibration | near_none | 5/12 | +4.86 | straight_border |
| calibration | near_stripes12 | 5/12 | +4.86 | straight_border |
| calibration | near_warp0.4+blur0.9+rows0.15+noise0.4+retime72 | 4/12 | +4.80 | sliver_border |
| calibration | near_warp0.5+blur0.9+rows0.15+noise0.4+retime72 | 5/12 | +4.42 | sliver_border |
| calibration | near_warp1.5+blur0.9 | 7/12 | +40.43 | straight_border |
| calibration | poly_blur0.9+noise8 | 7/10 | +inf | sliver_border |
| calibration | poly_blur0.9+stripes12 | 6/10 | +inf | sliver_border |
| calibration | poly_none | 7/10 | +inf | sliver_border |
| calibration | poly_warp3+blur0.9+noise8 | 7/10 | +58.36 | straight_border |
| evaluation | kevin_t_ngo-2102437977435893771 | 7/10 | +49.59 | straight_border |
| evaluation | near_blur0.9+dry16 | 8/12 | +4.85 | sliver_border |
| evaluation | near_blur0.9+dryhalf16 | 6/12 | +5.02 | sliver_border |
| evaluation | near_blur0.9+noise8 | 7/12 | +5.02 | sliver_border |
| evaluation | near_blur0.9+stripes12 | 6/12 | +5.02 | sliver_border |
| evaluation | near_blur0.9+stripes24 | 6/12 | +5.02 | sliver_border |
| evaluation | near_blur0.9 | 6/12 | +5.02 | sliver_border |
| evaluation | near_blur1.3 | 6/12 | +5.09 | sliver_border |
| evaluation | near_noise8+blur0.9 | 7/12 | +4.98 | sliver_border |
| evaluation | near_warp0.5+rows0.2+noise0.6+retime72 | 5/12 | +4.57 | sliver_border |
| evaluation | near_warp0.7+blur0.9+rows0.15+noise0.4+retime72 | 5/12 | +11.77 | straight_border |
| evaluation | near_warp0.7+blur0.9 | 6/12 | +11.77 | straight_border |
| evaluation | near_warp3+blur0.9 | 7/12 | +58.52 | straight_border |
| evaluation | poly_blur0.9+dry16 | 8/10 | +inf | sliver_border |
| evaluation | poly_blur0.9 | 7/10 | +inf | sliver_border |
| evaluation | poly_noise8+blur0.9 | 7/10 | +inf | sliver_border |

All 34 controls fail (`controls.py check` exit 0, 36/36 as required; the source clip passes at -1.00
and the replica at -0.18). Control names are `controls.py`'s: `near_` is round 3 through the named
filters, `poly_` the synthetic polygons. The polygons' dark field reaches the frame edge, so they
have the border class, show no slivers there, and fail `sliver_border` at distance inf. The attack
(`ATTACK`) is game.py plus a static 0.5 px contour warp, one frame held longer every 3 s, and faint
tonal rows 20-40 px apart with fine noise. Whole-frame `sliver` used to be its only rejecting row
(+0.14 to +0.23). On the 3% ring `sliver_border` rejects the warp 0.4 and 0.5 attacks at +4.80 and
+4.42 (round 3's frame carves 1.58-1.71 against the source's band of 3.17-4.13), with
`straight_border`, `straight_caption`, `sliver_caption` and `boil` (about 1.10 against 1.29-1.48)
also failing; `straight_border` rejects the warp 0.7 attack at +11.77. `controls.py selftest
<pack dir> --near <round 3>` exits 0: game.py's filter fails 7 rows on polygons and 6 on round 3,
and `ATTACK` fails `straight_border`, `straight_caption`, `sliver_border`, `sliver_caption` and
`boil`.

## Held-out and out-of-sample results

- Held-out source excerpts: 150/150 calibration and 150/150 evaluation pass every checked row, and
  each band passes 150/150 in both halves.
- Held out within the clip: the evaluation controls set no band, and all 16 fail. The evaluation
  excerpts set no band, and all 150 pass.
  None of this is out-of-sample validation: it is the same subject (see "One subject").
- Replica (its decoded mp4, judged as the source is): 0/14 rows fail, margin -0.20; the source's
  drawings re-encoded the same way also pass at -0.20. The closest row for both is the palette (ink 4
  levels off against a tolerance of 5).

Five choices were made after seeing evaluation or positive results, so their results are **not out of
sample**:

| Choice | Seen first |
|---|---|
| `ink_sd` left `CHECK` | an evaluation excerpt failed it |
| `offstep` changed to the pair form | an evaluation excerpt and the replica (0.23) failed the per-drawing form |
| the cap counts each control only at its strongest row | an evaluation excerpt failed under the per-row cap |
| `sliver` added to `CHECK` | chosen to catch the attack, after it passed |
| content classes, the `period` normalization and the anchored `boil` | proposed by the adjudication of a scene on another subject; the 3% border ring was set from where the source's frame stroke lies, not from any control or positive |

Every other choice was made on calibration data.

## Distance to source

A row's distance is |film value - source value| divided by |band edge - source value|, taking the
band edge on the film's side of the source value. It is 0 at the source value and 1 at either band
edge, however asymmetric the band. A row fails above 1. The film's distance is the mean over its
defined rows and ranks films that pass; its margin (largest row distance minus 1) says how far the
worst row is from the edge. The source scores 0.

## What the check cannot say

- **The attack is caught by round 3's own frame.** `sliver_border` and `boil` reject it because round
  3's frame stroke carves and boils less than the source's, a trait of that film, not of the filters.
  An attack on a film whose frame matches the source's has not been built.
- **Border presence is ink, not a stroke.** Any ring that is 10% ink counts, so a dark field reaching
  the edge (the polygons) has the class; its rows then fail rather than read n/a.
- **A film with no border or caption skips their rows.** A class the film lacks is n/a, neither
  pass nor fail, so a scene drawn without a frame line or caption panel is judged on the other rows
  only. A film that has the class but shows none of the measured thing fails the row. The caption detector also misses panels whose boiling outline breaks its seal, and it looks
  only in the top quarter, where the source puts them.
- **Subject still leaks into the interior rows.** `flat` and `holes` are measured
  over the whole ink, which is mostly the subject; only `straight`, `sliver` and `boil` moved to
  classes.
- **Composition and reading.** It checks mechanics, not whether a scene reads as the style. The
  research slice on style learning found no agreed metric or ground truth for style similarity, so
  human judgment on 1:1 crops stays the final gate.
- **Short films.** Bands come from excerpts of at least a third of the source (about 10 s); a
  shorter film is judged against bands it may not fit.
