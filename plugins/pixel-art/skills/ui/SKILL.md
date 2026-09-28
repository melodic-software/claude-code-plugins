---
description: "Create pixel-art UI with no external tools: window skins (RPG Maker MZ Window.png and generic 9-slice frames), icon grids (MZ IconSet.png), HUD elements, and bitmap fonts (a glyph grid or a BMFont .fnt beside it). The model authors a palette-locked spec, the bundled stdlib renderer writes the sheet, and a review loop grades the brief. Use when: 'window skin', '9-slice frame', 'icon set', 'HUD', 'bitmap font', 'Window.png', 'IconSet'. Not for a character sprite (use /pixel-art:sprite), a tileset (use /pixel-art:tileset), or a cutscene (use /pixel-art:scene)."
argument-hint: "<window, icons, hud, or font> [engine]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Author, render, and review pixel-art UI skins, icons, and fonts
---

# UI

Produce a window skin, icon set, HUD element, or bitmap font the target can use, and show it.

## 1. Brief

Ask only for what changes the pixels. State every unspecified field in one defaults line.

- **Kind**: window skin, icon set, HUD element, or bitmap font.
- **Target file**: the engine image or a plain sheet. Read the system-image rows in
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md) and the font line in the
  Godot section. Do not restate those tables.
- **Palette** and **mood** when the request leaves them open. Default palette is a small locked set.
- **Done**: 2 to 6 checks a picture can fail. Corners that survive a 9-slice stretch, and icons that read at 1x, are the default pair for a window and an icon set.

Write that brief beside the spec, in a file named brief.md, before the first render. A later run that finds it there reads it and does not ask again.

When the request is vague or high-stakes, offer `/planning:interview` if the planning plugin is installed. If it is not, or the user does not accept, continue with this brief. Do not start the interview unless the user accepts.

## 2. Choose the backend

Same rule as `/pixel-art:sprite`: [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native`
is the default.

## 3. Author

- **Window**: one frame the size `engine-layouts.md` gives for `Window.png` (or a 9-slice the brief
  names). Draw each region at that file's coordinates. `render.py` gives every frame in one spec the
  same size, so regions are composed into that single frame rather than stored as separate frames.
  A worked MZ skin is `${CLAUDE_PLUGIN_ROOT}/examples/ui/window_mz.py`.
- **Icons**: a uniform grid, `columns` from the engine row (MZ `IconSet.png` is 16 columns).
- **HUD**: one element or a strip, palette-locked, readable at 1x.
- **Font**: a glyph grid (one cell per character, in a stated order) or the same grid plus a BMFont
  `.fnt` whose `page` file is `sheet.png`. Nearest-neighbor only. No anti-aliased system font.

The spec palette is an inline object of one-character keys, as `render.py`'s docstring describes.
`.` is transparent.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 4
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. Keep the spec, `brief.md`, and the generator
beside the output.

## 5. Review loop

Read `preview.png`. Every round, list each done criterion in `brief.md` as pass or fail with a
one-line reason. Also check 9-slice corners stay square, icon silhouettes read at 1x, and glyph
cells do not touch the cell edge. Stop when every criterion passes, or after the round budget
(typically 2 to 4) with the failing criteria named.

## 6. Deliver

Report `sheet.png` at 1x under the engine filename (`Window.png`, `IconSet.png`, or the font page),
`sheet.json`, the `.fnt` when a bitmap font was requested, the preview, and the gallery.

## Next

/pixel-art:scene to use the skin, icons, or font in a scene.

## Gotchas

- `sheet.png` is the engine asset. `preview.png` is for review.
- A 9-slice corner that is not a solid block will tear when the engine stretches the edges.
- Icon 0 on an MZ `IconSet.png` is still a cell. Do not shift the grid to skip it.
