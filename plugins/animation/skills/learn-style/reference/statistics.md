# Style statistics: what they measure, how bands are set, which ones separate styles

Every number here comes from `inkstats.py` and `learn.py` runs on 2026-09-24 over nine films
decoded to distinct drawings: the shfred0 source (239 drawings), its rotoscoped replica (a
same-style control that no band was learned from), round 3 (a hand-authored replica of the same
shots that the user judged "not one for one"), three clips in other styles (a kevin_t_ngo spiral
engraving, a kevin_t_ngo torn-paper collage, a BiosRiosz anime duel), and three versions of the
validation scene "the keeper". Treat the bands as this pack's, not as laws: a new pack gets its
own from its own source.

## Contents

- The statistics
- How a band is set
- Which statistics separate
- Distance to source
- Regions: props, dark fields, the splat
- What the check cannot say

## The statistics

Per drawing, with ink and paper at the gray histogram modes and T at their midpoint:

| Stat | Measures | Knob |
|---|---|---|
| `soft` | mid-gray pixels per ink edge pixel: the edge ramp width in px (blur, anti-aliasing, soft brush) | texture |
| `w10` `w50` `w90` | ink stroke width, 2x the distance transform on its ridge | line |
| `pw50` | paper width median: the cream gaps, gouges and slivers between strokes | line, texture |
| `rough` | raw contour length over its 4 px polygon approximation, minus 1: edge wobble | line |
| `straight` | share of contour length in straight runs of 30 px or more: ruled lines | line, backgrounds |
| `specks`, `gaps` | ink and paper islands of 2-200 px per megapixel | texture |
| `holes` | paper share inside the ink after a 7 px closing: streaks and gouges in masses | texture |
| `ink_sd`, `paper_sd` | gray standard deviation inside eroded ink and paper: dry brush, grain | texture |
| `field_sd` | the same inside the largest connected ink area only: the texture of the biggest dark field | texture, backgrounds |
| `flat` | dark drawings only (ink 50% or more): share of mostly-ink 32 px blocks that lie fully inside eroded ink with gray sd under 2, the balance of flat black to textured ink | texture, backgrounds |
| `ink` | ink coverage | color |
| `boil` | on held pairs (shift under 1 px, ink change under 1 point), ink/paper disagreement per edge pixel: mean edge displacement between two drawings of one pose | line, movement |
| holds | each drawing's duration in 24 fps frames, on 1s/2s/3s/4+; drawings per second | frame rate |

`--region X,Y,W,H --t T0-T1` measures one box over a time window, `--cuts` makes each shot a
segment, and `--pack` prints each row, the distance to source, and exits 1 on any failing row.

## How a band is set

`learn.py` cuts the source into nine 3.35 s segments. For each statistic, the raw band spans the
lowest to highest segment median. Held-out validation learns a raw band from some segments and
tests the median of the rest, over 13 splits: alternate segments and first/second half, both
ways, and each segment left out in turn. Without widening, 125 of 156 held-out tests pass
(80.1%).

The widening is chosen for discrimination, not coverage. A statistic is widened by its largest
held-out miss, but never past half (`CLEAR`) of the smallest margin by which a negative control
(round 3 and the three clips, given with `--negative`) lies outside its raw band. So a band that
a control fails keeps failing it by a clear margin, and a band no control fails gets full
held-out coverage. `style.json` `heldout.rule` records, per statistic, the held-out maximum miss,
the chosen widening, the held-out pass rate under it, and every control's margin:

| Stat | Band | Widening | Held-out max miss | Held-out pass | Round 3 | Round 3 margin (raw band) |
|---|---|---|---|---|---|---|
| soft | 2.37-2.84 | 3.5% | 3.5% | 13/13 | 0.942 | +61.7% |
| w50 | 7.68-20.8 | 4.0% | 11.1% | 11/13 | 16 | 0 |
| w90 | 21.6-124 | 1.6% | 32.1% | 11/13 | 50 | 0 |
| pw50 | 6.0-8.5 | 6.2% | 20.1% | 12/13 | 8 | 0 |
| rough | 0.047-0.086 | 9.9% | 9.9% | 12/13 | 0.056 | 0 |
| holes | 0.003-0.070 | 56.6% | 56.6% | 12/13 | 0.020 | 0 |
| ink_sd | 2.16-8.81 | 9.5% | 28.5% | 11/13 | 1.94 | +18.9% |
| paper_sd | 0.49-11.0 | 38.1% | 38.1% | 12/13 | 3.00 | 0 |
| field_sd | 2.13-8.58 | 8.9% | 27.8% | 11/13 | 1.92 | +17.8% |
| flat | 0.18-0.80 | 9.2% | 37.0% | 8/11 | 0.358 | 0 |
| boil | 2.23-5.50 | 7.8% | 7.8% | 12/13 | 2.78 | 0 |
| per second | 7.41-8.37 | 2.6% | 2.6% | 13/13 | 8.01 | 0 |

Drawings per second gets the same rule from segment rates. The palette tolerance is the largest
channel difference between a segment's median ink or paper colour and the clip's (3 levels).
`field_sd` is also checked per shot of at least 8 drawings, against a band widened by the full
held-out miss (1.69-10.1), since that row asks only whether every shot's dark field is textured;
shfred0's 0.5 s flash (4 drawings) has a dark-field sd of 1.23.

## Which statistics separate

Check rows failed under the final bands, with margins outside the band:

| Film | Rows failed | Distance | Failing rows |
|---|---|---|---|
| source | 0/21 | 0.000 | none |
| replica | 0/21 | 0.111 | none |
| round 3 | 3/21 | 0.834 | soft 0.94 (+60%), ink_sd 1.94 (+10%), field_sd 1.92 (+10%) |
| spiral | 21/22 | 2.519 | 11 of 12 film rows, every shot's dark field, palette |
| collage | 19/23 | 6.407 | 10 of 12 film rows, 7 shots' dark fields, palette |
| anime | 24/25 | 17.854 | 11 of 12 film rows, every shot's dark field, palette |
| scene round 1 | 0/17 | 0.509 | none |
| scene round 2 | 1/17 | 0.347 | flat 0 (no flat black at all) |
| scene round 3 | 0/17 | 0.159 | none |

Read:

- **Round 3 is caught by `soft`, `ink_sd` and `field_sd`.** It has hard two-tone edges and flat
  gray-free ink. The discrimination rule keeps `ink_sd` and `field_sd` from widening past it.
- **Other styles:** `soft`, `rough`, `ink_sd`, `field_sd`, `boil`, drawings per second and the
  palette fail all three.
- **Not checked:** `ink`, `w10`, `specks` follow the subject; `straight` and `gaps` contain every
  control after held-out widening.

## Distance to source

`distance` is the mean over the checked statistics of |film median - source median| divided by
the band's half-width: 0 is the source, 1 is a band edge on average. It ranks films that all pass.
Held-out source parts score 0.096-0.139 (alternate and half splits) and 0.164-0.502 for single
3.35 s segments (median 0.376). The replica scores 0.111; the scene went from 0.509 (round 1) to
0.347 (round 2) to 0.159 (round 3), closer than round 3's 0.834.

## Regions: props, dark fields, the splat

- **Props.** Eight source prop boxes (inkwell, notes, shelves, wall papers, lab table, monitor,
  mug, building) measure `soft` 2.27-2.57, `rough` 0.036-0.090, `straight` 0.32-0.71, `ink_sd`
  0.74-16.5, `w50` 4.4-70. The scene's five prop boxes: `soft` 2.38-2.56, `rough` 0.052-0.084,
  `straight` 0.36-0.54, `ink_sd` 2.42-5.67, `w50` 8-16, inside both.
- **Dark fields.** About half the source's dark area is flat black (`flat` 0.537, 32 px blocks,
  sd under 2); the scene's is 0.472 (-12%). A scene carved everywhere scores 0 and fails.
- **The splat.** The source's own splat window (3.2-3.84 s, drawings 25-29) measures `w50` 18,
  `pw50` 8; the scene's splat shot measures 18 and 8.

## What the check cannot say

It checks the mechanics of a style, not whether a scene is good or reads as the style: the
research slice on style learning found no agreed metric or ground truth for style similarity, so
human judgment on 1:1 crops stays the final gate.
