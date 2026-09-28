---
description: "Create pixel-art tilesets with no external tools: terrain, autotiles (RPG Maker MZ A1-A5 and B-E, blob-47, 16-tile corner sets), seamless backgrounds, and parallax layers, laid out as the target engine's sheet. The model authors a palette-locked spec or a procedural generator, the bundled stdlib renderer writes the sheet, and a render-review loop grades the brief. Use when: 'tileset', 'autotile', 'terrain tiles', 'blob tileset', 'parallax background', 'RPG Maker tileset', 'seamless tile'. Not for a single sprite or icon (use /pixel-art:sprite), a character walk cycle (use /pixel-art:animate), or a cutscene (use /pixel-art:scene)."
argument-hint: "<terrain or set> [engine] [tile size]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Author, render, and review an engine tileset or parallax
---

# Tileset

Produce a tileset or parallax layer the target engine can load, and show it.

## 1. Brief

Ask only for what changes the pixels. State every unspecified field in one defaults line.

- **Subject** and **set**: seamless single tile, blob-47, 16-tile corner, RPG Maker quarter-tile block, or parallax layers.
- **Tile size** and **sheet**: the engine cell and file. Read [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md)
  and [`craft-tiles.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-tiles.md). Do not restate their tables.
- **Palette**, **view**, and **mood** when the request leaves them open. Default palette is a small locked set; default view is top-down for terrain.
- **Done**: 2 to 6 checks a picture can fail. A seam on a 3x3 repeat and a locked palette are the default pair.

Write that brief beside the spec, in a file named brief.md, before the first render. A later run that finds it there reads it and does not ask again.

When the request is vague or high-stakes, offer `/planning:interview` if the planning plugin is installed. If it is not, or the user does not accept, continue with this brief. Do not start the interview unless the user accepts.

## 2. Choose the backend

Same rule as `/pixel-art:sprite`: [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native`
is the default. A missing configured backend is named in one line and the render falls back to native.

## 3. Author

Draw the set `craft-tiles.md` names for that engine. Quarter-tile targets are the source block (the
engine composes the final shapes), not 48 hand-drawn tiles, unless the brief asks for the composed
proof. Blob and corner sets are the full tiles the engine samples. Parallax layers follow the depth
rules in `craft-tiles.md`: slower, darker, and less detailed as they recede, and the scroll step
divides the loop width.

Prefer a short procedural generator when the sheet is larger than a few tiles. A worked A2 ground
sheet is `${CLAUDE_PLUGIN_ROOT}/examples/tileset/a2_ground.py`. The spec palette is an inline
object of one-character keys, as `render.py`'s docstring describes. `.` is transparent.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 4
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. Keep the spec, `brief.md`, and the generator
beside the output.

## 5. Review loop

Read `preview.png`. Every round, list each done criterion in `brief.md` as pass or fail with a
one-line reason. Also check seams on a repeat (the generator or a 3x3 preview), edge-band thickness
on an autotile, and that a B sheet's top-left cell is blank when the target requires it. Stop when
every criterion passes, or after the round budget (typically 2 to 4) with the failing criteria named.

## 6. Deliver

Report `sheet.png` at 1x under the filename the engine expects, `sheet.json`, the preview, and the
gallery. Name the engine folder (`img/tilesets` for RPG Maker MZ).

## Next

/pixel-art:scene to place the tiles in a scene or parallax backdrop.

## Gotchas

- `sheet.png` is the engine asset. `preview.png` is for review.
- An RPG Maker B-E sheet starts with a blank cell. See `engine-layouts.md`.
- Quarter edges must match every partner quarter. A seam that only shows up in a composed shape is
  still a fail.
