---
description: "Create pixel-art tilesets with no external tools: terrain, autotiles (RPG Maker MZ A1-A5 and B-E, blob-47, 16-tile corner sets), seamless backgrounds, and parallax layers, laid out as the target engine's sheet. The model authors a palette-locked spec or a procedural generator, the bundled stdlib renderer writes the sheet, and a render-review loop iterates until the seams read. Use when: 'tileset', 'autotile', 'terrain tiles', 'blob tileset', 'parallax background', 'RPG Maker tileset', 'seamless tile'. Not for a single sprite or icon (use /pixel-art:sprite), a character walk cycle (use /pixel-art:animate), a window skin or icon set (use /pixel-art:ui), an effect sheet (use /pixel-art:vfx), or an HTML cutscene (use /pixel-art:scene)."
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

Pin down, from the request or by asking (ask only for what changes the output):

- **Subject**: terrain, water, wall, building, or a background, and the mood.
- **Set**: seamless single tile, blob-47, 16-tile corner, RPG Maker quarter-tile block, or parallax layers.
- **Tile size and sheet**: the engine cell and which file (A2, B, a Godot atlas, a plain strip). Read
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md) and
  [`craft-tiles.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-tiles.md). Do not restate their tables.
- **Palette**: a color count or a short list. Fewer colors read better.

Vague request: pick defaults, state them in one line, proceed.

Write `brief.md` beside the spec before the first render, with 2 to 6 done criteria, as
[`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md) describes. A later run that finds it there
reads it and does not ask again. Every review round lists each done criterion as pass or fail.

## 2. Choose the backend

Same rule as `/pixel-art:sprite`: [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native`
is the default. A missing configured backend is named in one line and the render falls back to native.

## 3. Author

Draw the set `craft-tiles.md` names for that engine. Quarter-tile targets are the source block (the
engine composes the final shapes), not a hand-drawn tile for every composed shape, unless the brief
asks for that proof. Blob and corner sets are the full tiles the engine samples. Parallax layers
follow the depth rules in `craft-tiles.md`: slower, darker, and less detailed as they recede, and
the scroll step divides the loop width.

Prefer a short procedural generator when the sheet is larger than a few tiles. A worked A2 ground
sheet is `${CLAUDE_PLUGIN_ROOT}/examples/tileset/a2_ground.py`. Keep the palette locked in the spec.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 4
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. Keep the spec and the generator beside the output.

## 5. Review loop

Read `preview.png` and critique it against the brief and `craft-tiles.md`: seams on a repeat (the
generator or a 3x3 preview), edge-band thickness on an autotile, a center that does not shout the
grid, and a blank top-left cell when the target sheet requires one. Fix the spec or generator,
re-render, re-read. Stop when it reads at 1x or after the user's direction says so; typically 2 to
4 rounds. Name the remaining weaknesses honestly.

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
