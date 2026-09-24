# Style statistics: what they measure and which ones separate styles

Every number here comes from `inkstats.py` runs on 2026-09-24 over seven films decoded to distinct
drawings: the shfred0 source (239 drawings), its rotoscoped replica (independent same-style
control, 239/239 per-drawing pass), round 3 (a hand-authored replica of the same shots that the
user judged "not one for one"), three clips in other styles (a kevin_t_ngo spiral engraving, a
kevin_t_ngo torn-paper collage, a BiosRiosz anime duel), and the validation scene "the keeper".
Treat the bands as this pack's, not as laws: a new pack gets its own from its own source.

## Contents

- The statistics
- How a band is set
- Which statistics separate
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
| `ink` | ink coverage | color |
| `boil` | on held pairs (shift under 1 px, ink change under 1 point), ink/paper disagreement per edge pixel: mean edge displacement between two drawings of one pose | line, movement |
| holds | each drawing's duration in 24 fps frames, on 1s/2s/3s/4+; drawings per second | frame rate |

## How a band is set

The source is cut into 3.35 s segments (nine on a 30 s clip), each segment's median taken, and
the band runs from 0.9 x the lowest to 1.1 x the highest segment median; drawings per second gets
15% either side, and the ink and paper colours 8 levels per channel. The 10% widening and the
15% rate tolerance are judgment, chosen so the replica, the independent same-style control,
passes: its `soft` sits at 2.375, just under the raw segment range of 2.459-2.747. A film passes a
statistic when its median over drawings lies inside the band.

## Which statistics separate

Film medians against the woodcut-ink bands (bold: outside):

| Stat | Band | Source | Replica | Round 3 | New scene | Spiral | Collage | Anime |
|---|---|---|---|---|---|---|---|---|
| soft | 2.21-3.02 | 2.54 | 2.38 | **0.94** | 2.39 | **1.63** | **13.1** | **38.7** |
| w50 | 7.2-22 | 16 | 16 | 16 | 20.2 | **4** | 21.6 | **7.19** |
| w90 | 19.8-134 | 60 | 58 | 50 | 52 | **10** | **156** | 126 |
| pw50 | 5.75-8.8 | 8 | 8 | 8 | 6 | **11** | **5.6** | **4** |
| rough | 0.047-0.086 | 0.071 | 0.069 | 0.056 | 0.073 | **0.096** | **0.104** | **0.110** |
| straight | 0.34-0.73 | 0.54 | 0.55 | 0.70 | 0.49 | 0.56 | **0.29** | 0.48 |
| gaps | 37-205 | 65 | 65 | 58 | 101 | **209** | 37.1 | 140 |
| holes | 0.006-0.049 | 0.021 | 0.022 | 0.020 | 0.043 | **0.111** | 0.014 | 0.011 |
| ink_sd | 2.15-8.86 | 4.12 | 3.60 | **1.94** | 2.73 | **20.8** | **21.8** | **27.6** |
| paper_sd | 0.71-8.75 | 2.52 | 1.95 | 3.00 | 1.50 | 1.45 | **25.5** | **33.6** |
| boil | 2.18-5.61 | 2.84 | 2.79 | 2.78 | 2.56 | **0.03** | **1.81** | **0.86** |
| per second | 6.7-9.1 | 7.9 | 7.9 | 8.0 | 8.0 | **9.13** | **13.6** | **22.5** |
| checks passed | | 14/14 | 14/14 | 12/14 | 14/14 | 3/14 | 3/14 | 4/14 |

Read:

- **Separate a near miss (round 3):** `soft` and `ink_sd`. Round 3 drew hard two-tone edges with
  no soften (0.94 px of ramp against 2.54) and flat ink with no dry-brush gray (1.94 against 4.12).
  Those are the two measured reasons it reads as a vector copy. Shot for shot, `straight` (6 of 9
  segments out: ruled lines where the source draws by hand) and `rough` (3 of 9) separate it too,
  but only against the same shots.
- **Separate other styles:** `soft`, `rough`, `ink_sd` and `boil` separate all three; `w50`,
  `w90`, `pw50`, `per_second` and the palette separate most. Each of the three fails 10 or 11 of 14.
- **Do not separate:** `ink` coverage, `w10` and `specks` vary more between the source's own shots
  than between styles; they describe the subject, not the style, and are not checked.

## What the check cannot say

It checks the mechanics of a style, not whether a scene is good or reads as the style: the
research slice on style learning found no agreed metric or ground truth for style similarity, so
the human judgment on 1:1 crops stays the final gate. The bands come from the source itself, so
the source passes by construction; the replica is the evidence that a same-style film passes, and
the three clips that a different style fails. `straight` separates round 3 only shot for shot, so
it cannot catch that near miss on a new subject; it stays checked because it separates the collage.
