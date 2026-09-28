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

Follow [`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md). That file is the only copy of the
fields: subject, style references, proportions, size, palette, view, mood, target, and 2 to 6 done
criteria. Ask only what changes the output. State every unspecified field as a default in one line.

Write `brief.md` beside the spec before the first render. A later run that finds it there reads it
and does not ask again.

When the request is vague or high-stakes, offer `/planning:interview` (if the planning plugin is
installed). Planning owns a numbered-question brief. If planning is not installed, or the user does
not accept, continue with the in-skill brief, which is the default and works alone. Do not start
the interview unless the user accepts.

## 2. Choose the backend

Read [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native` is the default and
always available. Honor `${user_config.backend}` when it names another backend and that backend
is present; when it is absent, say so and fall back to `native`. Every backend honors the same
artifact contract: the spec and the files in step 4.

## 3. Author

Write the spec that `render.py` reads (its docstring is the format). Two authoring modes:

- **Hand-authored grid**: small sprites (up to about 24x24), icons, faces. Write rows directly.
- **Procedural generator**: larger sprites or families of variants. Write a short Python script
  that draws with primitives (rects, ellipses, lines) onto a material grid, then applies shading
  and outlining passes and emits the spec JSON. Materials map to color ramps (highlight, base,
  shadow, line), which keeps the palette locked and makes recolors one-line edits. For a
  character, start from [`character_kit.py`](${CLAUDE_PLUGIN_ROOT}/scripts/character_kit.py)
  (proportion presets `chibi`, `standard`, `tall`; head and hair shapes; clothing layers; the
  shading and selective-outline passes; direction mirroring that shades again). Adapt those
  pieces. A worked 4-direction walker is
  [`examples/kit-walker/walker.py`](${CLAUDE_PLUGIN_ROOT}/examples/kit-walker/walker.py).

The spec `palette` may be an inline object, a bundled preset name, or a path to a project palette
file ([`palettes/README.md`](${CLAUDE_PLUGIN_ROOT}/palettes/README.md)). When the project has
`pixel-art-palette.json` (or another path its `CLAUDE.md` names), use that path instead of
inventing colors. Do not retype a preset by hand. Images from another backend are snapped with
`render.py --snap` (see [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md)), not by eye.

Apply [`craft-static.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-static.md): readable silhouette
first, one light direction, hue-shifted ramps, selective outline, no pillow shading, no banding,
no dithering on small sprites.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 8
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output directory, first match wins: an explicit path in the request; an assets location the
project declares in its `CLAUDE.md` or rules; `${user_config.output_dir}` (empty or unexpanded
means unset); otherwise ask. Keep the
spec, `brief.md`, and the generator beside the output so the next iteration edits source, not pixels.

## 5. Review loop

Read `preview.png` with the Read tool. Every round, list each done criterion in `brief.md` as pass
or fail with a one-line reason, and check [`craft-static.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-static.md)
where a criterion does not already cover it: silhouette at 1x, part separation, light consistency,
outline, stray pixels, palette discipline. Fix the spec or generator, re-render, re-read. Stop when
every done criterion passes, or after the round budget (typically 2 to 4) with the failing criteria
named. The user's direction can end the loop earlier.

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
