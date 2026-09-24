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
| Texture | 2.5 px soft edge ramp, gray inside the ink (sd 4.1, 3.9 in the largest dark field), clean paper; 65 paper slivers and 20 ink specks per megapixel | measured |
| Backgrounds | graphic, same ink and boil as the figures; whole scenes invert (cream light on black, black masses on cream); figures black with a broken cream outline; a hand-lettered lowercase caption in a marker box, top left, typing on | judgment |

## Authoring in it

`style.json` `brush` holds the defaults that passed validation:

- Organic masses: ink.js `inkFill` (width 12, pitch 0.78, dryBrush 0.1, overshoot 0.8).
- Props: never a filled polygon. Overlapping `inkFill` strokes (width 11, pitch 0.62) along the
  prop's main direction, then every edge re-stroked by hand 5 px wide, running past the corners so
  the stroke ends show; hatch light props with 7 px strokes every 24 px.
- Gray inside the ink: dense dry-brush strokes at gray 32 (`#231f1c`, under ink + 16 so edges
  stay sharp) over masses and the carved band of dark fields; props get a darker one (`#1e1a17`).
- Large dark areas: carve only a band near the edge (the upper 18% of a sea) with rows of cream
  gouges about 9.5 px wide every 24 px, 80-280 px long, and leave the rest flat black: about half
  the source's dark area is flat.
- Splats and transitions are solid ink growing on cream, with a few carved slivers.
- Boil: every drawing, slide each brushed stroke's ends up to 18 px, shift it up to 5.5 px
  sideways, and shake solid vertices about 8 px.
- Step every element at 8 drawings a second, finish each frame with a gaussian soften of sigma
  0.89 px, and frame it with a 17 px marker border 17.5 px in.

## Validation

"the keeper" (10 s: a storm at sea, a lighthouse beam that finds a boat, an ink splat, dawn),
authored in code on a subject the source never shows, rendered at 1762x982 and measured from its
mp4 with its own shot cuts, passes the check 17/17 at a distance of 0.159 from the source (the
replica scores 0.111, round 3 0.834). Film medians against the source: stroke width 16.2 (16),
cream gap 8 (8), gray inside the ink 3.79 (4.12), roughness 0.070 (0.071), flat black 0.472
(0.537). Per shot (storm, night, splat, dawn): stroke width 18, 16, 18, 16; cream gap 8 in every
shot; dark-field sd 4.63, 3.54, 4.53, 2.83. The splat shot matches the source's own splat window
(stroke width 18, cream gap 8). Its five prop boxes fall inside the pack bands and inside the
range of eight source prop boxes on edge softness, roughness, straightness, gray inside the ink
and stroke width. Round 3 fails edge softness, gray inside the ink and dark-field texture; clips
in three other styles fail 19 to 24 of their rows. The full tables are in the learn-style skill's
`reference/statistics.md`.

Where it still differs, on 1:1 crops next to the source:

- The distant lighthouse at dawn is 85 px wide, so its box's cream gap (18 px) is the paper
  around a small shape, not a stroke gap.
- Its seas and skies are horizontal carving; the source's dark fields are architecture (shelves,
  windows, walls), so the scene reads as a woodcut seascape rather than as the source's interiors.
