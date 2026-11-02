# Boards

Where the project has its own tokens or conventions, they win over anything here. The numbers in
the snippets are fallbacks: reach for one only when no project token covers it, and say which
fallback you used.

## Lane grid: `lane-grid`

Why: one template places every tile; widths come from variables.

```text
.board {
  lanes: [edge] 1fr [wide] 2u [main] min(70ch, 100%) [wide] 2u [edge] 1fr;
}

.board > .banner {
  lane: wide;
}
```

Rules:

- Every tile must be assigned a lane. An unassigned tile lands in the edge lane.
- Every direct child of a board is a tile. Wrap a run of loose labels in one tile.
- Change a width by overriding `--main`, not by writing a new lane template.
- In a pass over an existing board, replace each centered `fixed-width` frame with the lane grid,
  and keep the frame's width as `--main` on its section.
- Where the authoring tool has no child selectors, each tile sets its own `lane` to `main`,
  `wide` or `edge`; the lane template goes wherever the project defines reusable styles.

## Stacked tiles: `stacked-tiles`

Why: overlapping tiles share one cell instead of using fixed offsets.

- Put every overlapping tile in the same cell and order them with `layer`.
- Let the cell take the size of its largest tile, so text in a lower layer never clips.
