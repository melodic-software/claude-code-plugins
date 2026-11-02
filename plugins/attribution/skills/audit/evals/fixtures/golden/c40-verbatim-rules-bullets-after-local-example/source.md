# Ferro practices

Synthetic source page for the attribution golden set. Ferro is a fictional interface toolkit
invented for these fixtures. Nothing on this page describes a real product or reproduces text
from a real page.

Canonical location for the purposes of this case: `https://example.invalid/ferro/practices/PRACTICES.md`.

## Purpose

A list of Ferro board and motion practices for agents to know and reach for. Entries that were
removed were removed on purpose; do not add them back.

## Boards

### Lane grid

One template places every tile on a board, and widths come from variables rather than from new
templates.

- Every tile must be assigned a lane of the board. An unassigned tile lands in the edge lane.
- Every direct child of a board is a tile. Wrap a run of loose labels in one tile.
- Change a width by overriding `--main`, not by writing a new lane template.
- In a pass over an existing board, replace each centered `fixed-width` frame with the lane grid,
  and keep the frame's width as `--main` on its section.

Put the lane template wherever the project defines reusable styles. Where the authoring tool has
no child selectors, as in Plankboard or Tilekit without a custom variant, each tile sets its own
`lane` to `main`, `wide` or `edge`.

### Stacked tiles

Tiles that overlap share one cell and are ordered by `layer`.

## Motion

### Quiet by default

Motion is opt-in. Wrap it in a `when motion` block so a viewer who turned motion off gets the
still version.

- Write the state change first and put the animation inside the `when motion` block. Do not
  remove animation afterwards with a global rule that sets every frame count to `0`.
- Color and brightness fades are not animation and can stay outside the block.
- Animation driven by a plugin checks the same setting with `motionAllowed()`.

## References

Each entry credits the people whose work it draws on.

- `lane-grid`: Orla Pennick, A calmer board template, 2024-03-11 · Dev Haskins, Lanes without breakpoints · Mirela Stoyan, The edge lane trick
- `fluid-lanes`: Dev Haskins, Lanes that size themselves, 2025-01-19 · Inez Valdemar, One template for every board
- `stacked-tiles`: Tobin Achterberg, Layers on a single cell, 2025-03-29
- `safe-centering`: Pia Marchetti, Centering that never clips, 2025-06-10
- `clip-over-crop`: Orla Pennick, Two better choices than crop, 2023-12-14
- `neighbor-spacing`: Inez Valdemar, Spacing that reads its neighbors, 2022-08-18 · Dev Haskins, The sibling selector
- `parent-gap`: Hollis Brandt and Yusra Okafor, The Pile, Tile Patterns · Hollis Brandt, Spacing from above, 2014-10-21
- `quiet-motion`: Saoirse Lindqvist, Motion as an opt-in, 2023-06-02 · Ruben Oyelaran, The still version first
