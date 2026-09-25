# woodcut-ink

Two-tone black ink on cream paper that looks cut and printed by hand: heavy brushed masses with
comb edges, chunky cream gouges carved through the black, solid black elsewhere, a soft edge, and
every mark redrawn on every drawing at about 8 drawings a second, mostly on 3s but not strictly.

**Credit.** A study of [@shfred0](https://x.com/shfred0)'s clip "Asked Claude Opus 5.5 to animate
its own life, from day 0 to now" ([post](https://x.com/shfred0/status/2102495989194236158),
2026-09-22). The pack holds only statistics measured from it (`style.json`); the clip, its frames
and its traces are not shipped.

## Knobs

Measured values come from `learn.py` over the clip and live in `style.json` under the key named;
judgment values come from viewing it and are labelled so.

| Knob | Value | Basis |
|---|---|---|
| Color | 2 tones and a gray ramp at the edges and in dry-brush streaks: `palette` | measured |
| Line | broad brush strokes, narrow cream gaps, edges rough but not ragged, about half the edge length in straight runs: `knobs.line` | measured |
| Movement | limited: pushes, pulls, growth and wipes rather than acting; nothing is ever still because every drawing is re-inked; transitions are ink splats that fill the frame, hard cuts and jagged wipes | judgment |
| Frame rate | on 3s at 24 fps with some drawings on 2s and 4s, boil on every hold: `knobs.frame_rate`, `timing` | measured |
| Camera | flat, one-point perspective for interiors; push-in, pull-back, tilt; no parallax, no motion blur | judgment |
| Texture | a soft edge ramp; gray inside the ink in irregular patches several px wide, never at one pitch; about half the dark area flat black; clean paper: `knobs.texture` | measured |
| Backgrounds | graphic, same ink and boil as the figures; whole scenes invert (cream light on black, black masses on cream); figures black with a broken cream outline; a hand-lettered lowercase caption in a marker box, top left, typing on | judgment |

## Authoring in it

`style.json` `brush` holds ink.js starting values from an earlier scene. The current check has not
validated them, and the independent review of that scene found these departures, which the check
now measures:

- Edges: props and masses are overlapping `inkFill` strokes with edges re-stroked past the corners,
  never a filled polygon. Polygon edges are too straight (`straight_border`) and too smooth (`rough`).
- Texture: gray inside the ink comes in irregular patches. Parallel dry-brush lines at a fixed pitch
  read as ribbed black; pixel noise lowers `grain` (`grain` and `period` are measured only).
- Carving: gouges are chunky and irregular, not long thin lines (`sliver`) or rows at one spacing.
- Solid black: leave about half of the dark area flat (`flat`); texturing all of it fails.
- Timing: step at about 8 drawings a second on 3s, but hold some drawings for 2 or 4 frames as the
  source does (`offstep`); a film strictly on 3s fails.
- Boil: redraw every mark each drawing, moving every contour a few px rather than a few far.

## Validation

The check in `style.json` `check` has not yet validated a new, untraced scene. The earlier scene
("the keeper") passed an earlier check that a blur and ruled stripes could satisfy, and is being
rebuilt. What the check separates, the control suite it is held to, and its held-out results are in
the learn-style skill's `reference/statistics.md`.
