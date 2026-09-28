---
description: "Create pixel-art effects with no external tools: particles, hit sparks, spell and explosion cycles, as sprite-sheet animations. RPG Maker targets the MV-style img/animations cell sheet. The model authors a palette-locked spec, the bundled stdlib renderer writes the sheet and a GIF, and a review loop grades the brief. Use when: 'hit spark', 'pixel effect', 'spell animation', 'explosion', 'particle sheet', 'MZ animation cells'. Not for a character walk cycle (use /pixel-art:animate), a still sprite (use /pixel-art:sprite), a cutscene (use /pixel-art:scene), or an Effekseer .efkefc file."
argument-hint: "<effect> [frame count] [engine]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Author, render, and review pixel-art effects and animation cells
---

# VFX

Produce a pixel-art effect as a sprite sheet the target engine can play, and show it.

## 1. Brief

Ask only for what changes the pixels. State every unspecified field in one defaults line.

- **Effect**: spark, slash, explosion, spell, or a particle cycle, and whether it loops.
- **Cells**: frame count and the engine cell. Read the animations row in
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md) and timing in
  [`craft-animation.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-animation.md). Do not restate their tables.
- **Sheet**: MV-style img/animations or a plain strip.
- **Palette** and **mood** when the request leaves them open. Default palette is a small locked ramp.
- **Done**: 2 to 6 checks a picture can fail. The impact frame reads brighter than the fade, and the palette stays locked, are the default pair.

MZ's native Effekseer format is not a pixel sheet. Say so and offer this skill's cell sheet instead. Do not write an Effekseer file.

Write that brief beside the spec, in a file named brief.md, before the first render. A later run that finds it there reads it and does not ask again.

When the request is vague or high-stakes, offer `/planning:interview` if the planning plugin is installed. If it is not, or the user does not accept, continue with this brief. Do not start the interview unless the user accepts.

## 2. Choose the backend

Same rule as `/pixel-art:sprite`: [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native`
is the default.

## 3. Author

One procedural `draw(frame)` so the effect grows, bursts, or fades in palette steps, not by alpha.
Hold the impact frame. A worked 5-column spark is `${CLAUDE_PLUGIN_ROOT}/examples/vfx/spark_mz.py`.
Name frames `fx0`, `fx1`, ... and list them under `animations` with `fps` or `durations_ms`.
`sheet.columns` is the engine's column count.

The spec palette is an inline object of one-character keys, as `render.py`'s docstring describes.
`.` is transparent. Every frame in one spec is the same size; split effects that need different
cell sizes into separate specs.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 2
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. Keep the spec, `brief.md`, and the generator
beside the output.

## 5. Review loop

Read `preview.png` (the Read tool shows a GIF's first frame only, so judge motion from the sheet).
Every round, list each done criterion in `brief.md` as pass or fail with a one-line reason. Also
check the silhouette grows or breaks on purpose, the impact frame is held, and colors stay on the
locked palette. Stop when every criterion passes, or after the round budget (typically 2 to 4) with
the failing criteria named.

## 6. Deliver

Report `sheet.png` at 1x, `sheet.json`, the GIF, and the gallery. For RPG Maker, the sheet belongs
in `img/animations` and the cell grid is the one in `engine-layouts.md`.

## Next

/pixel-art:scene to composite the effect into a scene.

## Gotchas

- `sheet.png` is the engine asset. `preview.png` and the GIF are for review.
- Do not fade with partial alpha. Step down a palette ramp, the same rule as `scene-canvas.md`.
- Effekseer files are out of scope. The delivered asset is the pixel cell sheet.
