# woodcut-ink

Two-tone black ink on cream paper that looks cut and printed by hand: heavy brushed masses with
comb edges, cream gouges carved through the black, a soft edge, and every mark redrawn on every
drawing at about 8 drawings a second.

**Credit.** A study of [@shfred0](https://x.com/shfred0)'s clip "Asked Claude Opus 5.5 to animate
its own life, from day 0 to now" ([post](https://x.com/shfred0/status/2102495989194236158),
2026-09-22). The pack holds only statistics measured from it (`style.json`); the clip, its frames
and its traces are not shipped.

## Knobs

Measured values come from `learn.py` over the 239 drawings of the clip; judgment values come from
viewing it and are labelled so.

| Knob | Value | Basis |
|---|---|---|
| Color | 2 tones: ink `#13110f`, paper `#efe9e0`; a gray ramp at the edges and in dry-brush streaks (`#46423e`, `#94908b`, `#bebab4`) | measured |
| Line | ink strokes 16 px median width (8-20 across drawings), cream gaps 8 px; edges rough (0.071) but not ragged; about half the edge length in straight runs | measured |
| Movement | limited: pushes, pulls, growth and wipes rather than acting; nothing is ever still because every drawing is re-inked; transitions are ink splats that fill the frame, hard cuts and jagged wipes | judgment |
| Frame rate | on 3s at 24 fps (92% of drawings), 7.9 drawings per second; boil on every hold, edges move 2.8 px between drawings of one pose | measured |
| Camera | flat, one-point perspective for interiors; push-in, pull-back, tilt; no parallax, no motion blur | judgment |
| Texture | 2.5 px soft edge ramp, gray inside the ink (sd 4.1), clean paper; 65 paper slivers and 20 ink specks per megapixel | measured |
| Backgrounds | graphic, same ink and boil as the figures; whole scenes invert (cream light on black, black masses on cream); figures black with a broken cream outline; a hand-lettered lowercase caption in a marker box, top left, typing on | judgment |

## Authoring in it

`style.json` `brush` holds the defaults that passed validation. In short: draw organic masses with
ink.js `inkFill` (width 12, pitch 0.78, dryBrush 0.1, overshoot 0.8) plus sparse lighter streaks
inset in each mass; draw architecture and props as solid fills whose vertices shake about 8 px per
drawing; carve large black areas with rows of cream gouges about 6.5 px wide every 16-20 px; slide
each brushed stroke's ends up to 18 px and shift it up to 5.5 px sideways every drawing; step every
element at 8 drawings a second; finish each frame with a gaussian soften of sigma 0.9 px; frame it
with a 17 px marker border 17.5 px in.

## Validation

"the keeper" (10 s: a storm at sea, a lighthouse beam that finds a boat, a cream splat, dawn),
authored in code on a subject the source never shows, rendered at 1762x982 and measured from its
mp4, passes the check 14/14. Round 3, a hand-authored replica of the source's own shots, fails
2 (edge softness 0.94, gray inside the ink 1.94); clips in three other styles fail 10 or 11. The
per-statistic table is in the learn-style skill's `reference/statistics.md`.

Where it still falls short, on 1:1 crops next to the source: the boat and lighthouse are clean
geometric solids, where the source builds even props from overlapping hand strokes; the scene is
less dense in fine line work (stroke width 20 against 16, cream gaps 6 against 8, both inside the
bands but off-centre); its night sky is a solid fill, so the gray inside its ink (2.7) sits near
the band's low edge.
