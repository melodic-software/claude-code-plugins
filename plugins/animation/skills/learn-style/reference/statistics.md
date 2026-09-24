# Style statistics: what they measure, how bands are set, which ones separate styles

Every number here comes from `inkstats.py` and `learn.py` runs on 2026-09-24 over eight films
decoded to distinct drawings: the shfred0 source (239 drawings), its rotoscoped replica (a
same-style control that no band was learned from), round 3 (a hand-authored replica of the same
shots that the user judged "not one for one"), three clips in other styles (a kevin_t_ngo spiral
engraving, a kevin_t_ngo torn-paper collage, a BiosRiosz anime duel), and two versions of the
validation scene "the keeper". Treat the bands as this pack's, not as laws: a new pack gets its
own from its own source.

## Contents

- The statistics
- How a band is set
- Which statistics separate
- Regions: props and dark fields
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
| `ink` | ink coverage | color |
| `boil` | on held pairs (shift under 1 px, ink change under 1 point), ink/paper disagreement per edge pixel: mean edge displacement between two drawings of one pose | line, movement |
| holds | each drawing's duration in 24 fps frames, on 1s/2s/3s/4+; drawings per second | frame rate |

`--region X,Y,W,H --t T0-T1` measures one box (a prop, a dark field) over a time window, and
`--cuts` makes each shot a segment.

## How a band is set

Held-out validation, not a chosen margin. `learn.py` cuts the source into nine 3.35 s segments
and, for each statistic, learns a band (lowest to highest segment median) from some segments and
tests the median of the rest, over 13 splits: alternate segments and first/second half, both
ways, and each segment left out in turn. Without widening, 125 of 156 held-out tests pass
(80.1%). A statistic's widening is the largest relative miss any held-out part needed, so its
final band spans all nine segment medians widened by that much:

| Stat | soft | w50 | w90 | pw50 | rough | holes | ink_sd | paper_sd | boil | field_sd | per second |
|---|---|---|---|---|---|---|---|---|---|---|---|
| widening | 3.5% | 11.1% | 32.1% | 20.1% | 9.9% | 56.6% | 28.5% | 38.1% | 7.8% | 27.8% | 2.6% |

Every held-out part passes the widened bands by construction, so the independent evidence is the
replica, which no band saw and which passes 19/19. The palette tolerance is measured the same way:
the largest channel difference between a segment's median ink or paper colour and the clip's
(3 levels). `field_sd` is checked per shot of at least 8 drawings: shfred0's 0.5 s flash (4
drawings) has a dark-field sd of 1.23 against its segments' 2.3-7.9.

## Which statistics separate

Film medians against the final bands (bold: outside). Round 3 and the replica are checked with
the source's shot cuts, the scenes with their own.

| Stat | Band | Source | Replica | Round 3 | Spiral | Collage | Anime | Old scene | New scene |
|---|---|---|---|---|---|---|---|---|---|
| soft | 2.37-2.84 | 2.54 | 2.38 | **0.94** | **1.63** | **13.1** | **38.7** | 2.39 | 2.46 |
| w50 | 7.11-22.2 | 16 | 16 | 16 | **4** | 21.6 | 7.19 | 20.2 | 16 |
| w90 | 14.9-161 | 60 | 58 | 50 | **9.99** | 156 | 126 | 52 | 32 |
| pw50 | 5.11-9.61 | 8 | 8 | 8 | **11** | 5.6 | **4** | 6 | 8 |
| rough | 0.047-0.086 | 0.071 | 0.069 | 0.056 | **0.096** | **0.104** | **0.110** | 0.073 | 0.085 |
| holes | 0.003-0.070 | 0.021 | 0.022 | 0.020 | **0.111** | 0.014 | 0.011 | 0.043 | 0.030 |
| ink_sd | 1.71-10.3 | 4.12 | 3.60 | 1.94 | **20.8** | **21.8** | **27.6** | 2.73 | 4.14 |
| paper_sd | 0.49-11.0 | 2.52 | 1.95 | 3.00 | 1.45 | **25.5** | **33.6** | 1.50 | 1.75 |
| boil | 2.23-5.50 | 2.84 | 2.79 | 2.77 | **0.03** | **1.81** | **0.86** | 2.56 | 3.10 |
| per second | 7.41-8.37 | 7.92 | 7.91 | 8.01 | **9.13** | **13.6** | **22.5** | 8 | 8 |
| field_sd | 1.69-10.1 | 3.91 | 3.45 | 1.92 | **20.5** | **12.6** | **22.8** | 2.71 | 4.07 |
| check rows passed | | 19/19 | 19/19 | 18/19 | 1/20 | 6/21 | 3/23 | 15/15 | 15/15 |

Read:

- **Separates the near miss (round 3): `soft` only.** Round 3 draws hard two-tone edges with no
  soften pass. Its gray inside the ink (1.94) failed the earlier margin-based band but sits inside
  the held-out band, because the source's own shots range down to 1.26 (the flash).
- **Separates other styles: `soft`, `rough`, `ink_sd`, `boil`, `per_second` and `field_sd`**
  fail all three clips; each clip fails 15 to 20 of its rows.
- **Does not separate, so not checked:** `ink` coverage, `w10` and `specks` follow the subject;
  under held-out bands `straight` (0.28-0.84) and `gaps` (29-241) contain every clip, so they were
  dropped from the check.
- **The old and new scene both pass.** The check cannot rank two passing scenes; the regional
  checks below and the 1:1 crops can. The new scene centres the medians the old one only fit:
  `w50` 16 (old 20.2), `pw50` 8 (old 6), `ink_sd` 4.14 (old 2.73) against the source's 16, 8
  and 4.12.

## Regions: props and dark fields

Source prop boxes (median over their drawings): `soft` 2.27-2.57, `rough` 0.036-0.090,
`straight` 0.32-0.71, `ink_sd` 0.74-16.5, `w50` 4.4-70 (inkwell, notes, shelves, wall papers,
lab table, monitor, mug, building). The validation scene's five prop boxes (two boats, two
lighthouses, the dawn boat) fall inside both those ranges and the pack bands: `soft` 2.39-2.56,
`rough` 0.063-0.085, `straight` 0.35-0.55, `ink_sd` 2.47-5.23, `w50` 8.2-12. Source dark fields
differ widely: the lab wall has a dark-field sd of 3.28, the rainy city 0.57.

## What the check cannot say

It checks the mechanics of a style, not whether a scene is good or reads as the style: the
research slice on style learning found no agreed metric or ground truth for style similarity, so
human judgment on 1:1 crops stays the final gate. A statistic that sits near a band edge (the new
scene's `rough` 0.085 against 0.086) passes but is not centred.
