---
description: "Create static pixel-art sprites (characters, items, icons, portraits, faces, battlers, props) as engine-ready PNG sheets with no external tools: the model authors a palette-locked spec or a procedural generator, the bundled stdlib renderer writes the files, and a render-review loop iterates until the sprite reads. Use when: 'make a sprite', 'pixel art of X', 'draw a 32x32 icon', 'character portrait', 'RPG Maker face', 'item icons', 'pixel-art character design'. Not for movement cycles (use /pixel-art:animate) or composed scenes and cutscenes (use /pixel-art:scene)."
argument-hint: "<what to draw> [size] [palette] [engine]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Author, render, and review a static pixel-art sprite
---

# Sprite

Produce a static sprite the user can drop into a game or project, and show it to them.

## 1. Brief

Pin down, from the request or by asking (ask only for what changes the output):

- **Subject and design**: what it is, key features, mood, reference styles.
- **Size**: grid per frame (16, 24, 32, 48, 64). Engine layouts dictate it when named.
- **Palette**: a named retro palette, a colour count, or free choice. Fewer colours read better.
- **View**: front, side, three-quarter, top-down, isometric.
- **Target**: engine or format (RPG Maker MZ, Godot, Aseprite, plain PNG) from
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md).

Vague request → pick defaults, state them in one line, proceed. Iteration beats interrogation.

## 2. Choose the backend

Read [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native` is the default and
always available. Honour `${user_config.backend}` when it names another backend and that backend
is present; when it is absent, say so and fall back to `native`. Every backend honours the same
artifact contract: the spec and the files in step 4.

## 3. Author

Write the spec that `render.py` reads (its docstring is the format). Two authoring modes:

- **Hand-authored grid**: small sprites (up to about 24x24), icons, faces. Write rows directly.
- **Procedural generator**: larger sprites or families of variants. Write a short Python script
  that draws with primitives (rects, ellipses, lines) onto a material grid, then applies shading
  and outlining passes and emits the spec JSON. Materials map to colour ramps (highlight, base,
  shadow, line), which keeps the palette locked and makes recolours one-line edits.

Apply [`craft-static.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-static.md): readable silhouette
first, one light direction, hue-shifted ramps, selective outline, no pillow shading, no banding,
no dithering on small sprites.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 8
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output directory, first match wins: an explicit path in the request; an assets location the
project declares in its `CLAUDE.md` or rules; `${user_config.output_dir}`; otherwise ask. Keep the
spec (and generator) beside the output so the next iteration edits source, not pixels.

## 5. Review loop

Read `preview.png` with the Read tool and critique it against the brief and the craft rules:
silhouette at 1x, part separation, light consistency, outline, stray pixels, palette discipline.
Fix the spec or generator, re-render, re-read. Stop when it reads well at 1x or after the user's
direction says so; typically 2 to 4 rounds. Name the remaining weaknesses honestly.

## 6. Deliver

Report the engine asset (`sheet.png`), `sheet.json`, the preview, and `index.html` from the
gallery. Give the user a way to see it: the gallery path, converted to a host path when the
session runs in WSL (`wslpath -w`), or send the preview file when a file-sending tool exists.

## Next

/pixel-art:animate <the same spec> to give the sprite movement cycles.

## Gotchas

- `sheet.png` is 1x on purpose; engines scale. Never ship `preview.png` as the asset.
- Palette keys are single characters and `.` is always transparent.
- Mirroring a side view for the opposite direction also flips the light; reshade when the light
  side matters (judgment, see `craft-animation.md`).
- Engine sheet sizes in `engine-layouts.md` marked derived come from documented ratios, not a
  stated number; check against the engine's sample assets when exactness matters.
