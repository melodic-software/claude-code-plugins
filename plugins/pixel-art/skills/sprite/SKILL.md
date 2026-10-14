---
description: "Static pixel-art sprites (characters, items, icons, portraits, faces, battlers, props) as engine-ready PNG sheets, rendered with no external tools and reviewed until they read. Use when asked to 'make a sprite', 'pixel art of X', 'draw a 32x32 icon', 'character portrait', 'RPG Maker face', 'item icons', or 'pixel-art character design'. Movement cycles: /pixel-art:animate; composed scenes: /pixel-art:scene."
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

Follow [`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md), the only copy of the fields
(including 2 to 6 done criteria). Ask only what changes the output; state every unspecified field
as a default in one line. Write `brief.md` beside the spec before the first render. A later run
that finds it there reads it and does not ask again.

When the request is vague or high-stakes, offer `/planning:interview` (if the planning plugin is
installed). Planning owns a numbered-question brief. If planning is not installed, or the user does
not accept, continue with the in-skill brief, which is the default and works alone. Do not start
the interview unless the user accepts.

## 2. Choose the backend

Read [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native` is the default and
always available. Honor `${user_config.backend}` when it names another backend. `${CLAUDE_PLUGIN_ROOT}/scripts/backends.py`
detects that backend, uses it when it is present, and otherwise prints one line and renders with
`native`. The backend is `native` (default) or `aseprite`. Both honor the same artifact contract:
the spec and the files in step 4.

## 3. Author

Write the spec that `render.py` reads (its docstring is the format). Two authoring modes:

- **Hand-authored grid**: small sprites (up to about 24x24), icons, faces. Write rows directly.
- **Procedural generator**: larger sprites or families of variants. Write a short Python script
  that draws with primitives (rects, ellipses, lines) onto a material grid, then applies shading
  and outlining passes and emits the spec JSON. Materials map to color ramps (highlight, base,
  shadow, line), which keeps the palette locked and makes recolors one-line edits.
  For a full-body humanoid character, adapt `${CLAUDE_PLUGIN_ROOT}/scripts/kit.py` instead of
  writing that machinery: it draws down, left, and up and mirrors for right, and one `down` frame
  is a static character. Portraits and faces stay hand-authored grids.

Set the spec `palette` to the project's palette file when it has one (`pixel-art-palette.json`, or
the path its `CLAUDE.md` names); otherwise to a bundled preset name or an inline object
([`palettes/README.md`](${CLAUDE_PLUGIN_ROOT}/palettes/README.md)). Never invent colors over a
project palette or retype a preset by hand. Snap images from another backend with
`render.py --snap` ([`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md)), not by eye.

Apply [`craft-static.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-static.md): readable silhouette
first, one light direction, hue-shifted ramps, selective outline, no pillow shading, no banding,
no dithering on small sprites.

## 4. Render

Output directory, first match wins: an explicit path in the request; an assets location the
project declares in its `CLAUDE.md` or rules; `${user_config.output_dir}` (empty or unexpanded
means unset); otherwise ask before rendering. Keep the spec, `brief.md`, and the generator beside
the output so the next iteration edits source, not pixels.

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/backends.py" <spec.json> --out <dir> --scale 8
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Pass `--backend <name>` when this request names one; otherwise pass
`--backend ${user_config.backend}` when that option is set, rather than relying on the environment
to carry it. Aseprite builds `source.aseprite` from the frame rows.

## 5. Review loop

Read `preview.png`. Every round, mark each done criterion in `brief.md` pass or fail with a
one-line reason, and check [`craft-static.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-static.md)
where no criterion covers it: silhouette at 1x, part separation, light consistency, outline, stray
pixels, palette discipline. Fix the spec or generator, re-render, re-read. Stop when every
criterion passes, or after the round budget (typically 2 to 4) with the failing criteria named,
or earlier at the user's direction.

## 6. Deliver

Report `sheet.png` (the engine asset), `sheet.json`, the preview, and the gallery `index.html`.
Give the user a way to see it: the gallery path (via `wslpath -w` when the session runs in WSL),
or the preview file sent with a file-sending tool when one exists.

## Next

/pixel-art:animate <the same spec> to give the sprite movement cycles.

## Gotchas

- `sheet.png` is 1x on purpose; engines scale. Never ship `preview.png` as the asset.
- Palette keys are single characters and `.` is always transparent.
- Mirroring a side view for the opposite direction also flips the light; reshade when the light
  side matters (judgment, see `craft-animation.md`).
- Engine sheet sizes in `engine-layouts.md` marked derived come from documented ratios, not a
  stated number; check against the engine's sample assets when exactness matters.
