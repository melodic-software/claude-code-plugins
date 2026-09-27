# Tile craft

One rule per line, source in brackets. "(judgment)" marks a rule no source states.

Sources: [Saint11 Tiles](https://saint11.art/img/pixel-tutorials/Tiles.gif),
[Saint11 Parallax](https://saint11.art/img/pixel-tutorials/Parallax.gif),
[boristhebrave, Classification of Tilesets](https://www.boristhebrave.com/2021/11/14/classification-of-tilesets/),
[RPG Maker, how autotiles work](https://www.rpgmakerweb.com/blog/classic-tutorial-how-autotiles-work),
[yxbh MV/MZ autotile spec](https://github.com/yxbh/tileset-format-specs/blob/HEAD/formats/rpg-maker-mv-mz/specs/autotiles.md),
[Slynyrd 23](https://www.slynyrd.com/blog/2019/11/12/pixelblog-23-parallax-scrolling).

## Seamless tiling (single source: Saint11 Tiles)

- Draw one master tile that wraps on all 4 edges: draw rough, offset 50% both ways, rework the
  center, offset back.
- Then draw the main edge tiles (top, middle, bottom); other shapes (tubes, corners) depend on the
  engine.
- Variants change only the tile center, so every variant still wraps.
- Verify by rendering a 3x3 repeat and checking the seams at 1x and upscaled (judgment).
- Avoid a single standout feature in a repeating tile; it exposes the grid (judgment).

## Grid and density

- One tile size per project, matched to the character height; see `craft-static.md` Grid size
  (judgment).
- RPG Maker MZ: 48x48 tiles, 24x24 quarters. [yxbh spec; RPG Maker autotiles]

## Autotile sets: pick by engine

The "Use when" column's Godot pairings are judgment; the Godot 3 bitmask mapping is unverified.

| Set | Drawn tiles | Covers | Use when |
|---|---|---|---|
| Blob | 47 full tiles | every edge + corner case | engine uses 8-neighbor bitmasks (Godot Match Corners and Sides, Tiled "blob") |
| Corner (Wang 2-corner) | 16 full tiles | corner-only transitions | engine matches corners only (Godot Match Corners) |
| RPG Maker quarter-tile | one 2x3 (floor) or 2x2 (wall) block | 48 floor / 16 wall shapes, composed by the engine | RPG Maker MV/MZ A1-A4 |

- Blob = 47 of the 256 edge-plus-corner combinations, because a corner counts only when both
  adjacent edges are filled. [boristhebrave; second source: redblobgames autotile article (no URL)]
- The corner-only set needs 16 tiles; that it equals marching squares is derived, not quoted.
  [boristhebrave]
- RPG Maker stores quarter pieces, not whole tiles; each final tile is 4 quarters (TL, TR, BL, BR),
  each quarter source always used in the same position. [RPG Maker autotiles; yxbh spec]
- Quarter = tile / 2 at any tile size. [yxbh spec]
- MZ floor autotiles compose 48 shapes from the 2x3 block, walls 16 from 2x2, waterfalls 4
  (MZ v1.10.0 `Tilemap` tables; see `engine-layouts.md` for its verification record).
- Trade-off: blob gives exact per-case control at 47 drawings; quarter-tile needs far fewer
  drawings, but every quarter edge must match every partner quarter (judgment).

## Drawing a quarter-tile block (judgment unless noted)

- The block's quarters are cut at tile / 2; design edges so any TL can sit beside any TR.
- Keep the edge band (outline, lip, shadow) the same thickness in every quarter.
- Test the composition by rendering the 48 floor shapes before shipping, not just the block.
- MZ A2 counter tiles shift the bottom 12px down. (MZ help; see `engine-layouts.md`)

## Parallax depth

- Layer position = (position - camera) x scroll factor + offset; UI factor 0; a foreground layer
  above 1 adds depth. [Saint11 Parallax]
- Far layers: slower, darker, less saturated, lower contrast, cooler, fewer details, fading toward
  the sky color. Near layers: faster, brighter, saturated, warmer, detailed. [Saint11 Parallax;
  Slynyrd 23]
- Pixel-perfect loops: farthest layer 1px per frame, each nearer layer the next integer rate; the
  per-frame step must divide the loop width (96px: 1, 2, 3, 4, 6, 8...). [Slynyrd 23]
- Never scroll at fractional pixel rates on screen; accumulate sub-pixel position and draw at the
  floored integer (judgment).
- 3-4 layers cover most scenes: sky, far, mid, near (judgment).
