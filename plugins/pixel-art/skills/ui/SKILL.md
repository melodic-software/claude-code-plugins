---
description: "Create pixel-art UI with no external tools: window skins (RPG Maker MZ Window.png and generic 9-slice frames), icon grids (MZ IconSet.png), HUD elements, and bitmap fonts (a glyph grid or a BMFont .fnt beside it). The model authors a palette-locked spec, the bundled stdlib renderer writes the sheet, and a render-review loop iterates until the skin reads. Use when: 'window skin', '9-slice frame', 'icon set', 'HUD', 'bitmap font', 'Window.png', 'IconSet'. Not for a single item icon or character (use /pixel-art:sprite), a tileset (use /pixel-art:tileset), an effect sheet (use /pixel-art:vfx), or a cutscene (use /pixel-art:scene)."
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

Follow [`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md) the same way `/pixel-art:sprite`
does, including the `brief.md` file, the one-line defaults, and the presence-gated
`/planning:interview` offer. Then add:

- **Kind**: window skin, icon set, HUD element, or bitmap font, and what it should feel like.
- **Target file**: the engine image or a plain sheet. Read the system-image rows in
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md) and the font line in the
  Godot section. Do not restate those tables.

## 2. Choose the backend

Same rule as `/pixel-art:sprite`: read [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md).
`native` is the default and always available. Honor `${user_config.backend}` when it names another
backend, and pass no `--confirm` until the user accepts a paid call. Generative backends fit UI
skins poorly; use one only when the request names it.

## 3. Author

- **Window**: one frame the size `engine-layouts.md` gives for `Window.png`, or a 9-slice the brief
  names. Draw each region at that file's coordinates. `render.py` gives every frame in one spec the
  same size, so regions are composed into that single frame rather than stored as separate frames.
  A worked MZ skin is `${CLAUDE_PLUGIN_ROOT}/examples/ui/window_mz.py`. Keep the 9-slice corners a
  solid block; the engine stretches the edges and the center.
- **Icons**: a uniform grid. `columns` is the IconSet.png row in `engine-layouts.md`.
- **HUD**: one element or a strip, palette-locked, readable at 1x.
- **Font**: a glyph grid (one cell per character, in a stated order). When the target wants BMFont,
  write the text `.fnt` the Godot font line in `engine-layouts.md` points at, with `sheet.png` as
  the page and one character entry per glyph using the rects in `sheet.json`. Nearest-neighbor
  only. No anti-aliased system font.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/backends.py" <spec.json> --out <dir> --scale 4
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

`backends.py` writes the same files `render.py` does. Pass `--backend <name>` when this request
names one; otherwise pass `--backend ${user_config.backend}` when that option is set, rather than
relying on the environment to carry it.

Output location resolves as in `/pixel-art:sprite`. Keep the spec and the generator beside the output.

## 5. Review loop

Read `preview.png` and critique it against the brief and the engine layout: 9-slice corners stay
square, icon silhouettes read at 1x, glyph cells do not touch the cell edge, and each window region
sits where `engine-layouts.md` puts it. Fix, re-render, re-read. Stop when it reads at 1x or after
the user's direction says so; typically 2 to 4 rounds. Name the remaining weaknesses honestly.

## 6. Deliver

Report `sheet.png` at 1x under the engine filename (`Window.png`, `IconSet.png`, or the font page),
`sheet.json`, the `.fnt` when a bitmap font was requested, the preview, and the gallery.

## Next

/pixel-art:scene to use the skin, icons, or font in a scene.

## Gotchas

- `sheet.png` is the engine asset. `preview.png` is for review.
- A 9-slice corner that is not a solid block will tear when the engine stretches the edges.
- Icon 0 on an MZ `IconSet.png` is still a cell. Do not shift the grid to skip it.
