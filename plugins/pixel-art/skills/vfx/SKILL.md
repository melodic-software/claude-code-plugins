---
description: "Create pixel-art effects with no external tools: particles, hit sparks, spell and explosion cycles, as sprite-sheet animations. RPG Maker targets the MV-style img/animations cell sheet. The model authors a palette-locked spec, the bundled stdlib renderer writes the sheet and a GIF, and a render-review loop iterates until the motion reads. Use when: 'hit spark', 'pixel effect', 'spell animation', 'explosion', 'particle sheet', 'MZ animation cells'. Not for a character walk cycle (use /pixel-art:animate), a still sprite (use /pixel-art:sprite), a tileset (use /pixel-art:tileset), a window skin (use /pixel-art:ui), a cutscene (use /pixel-art:scene), or an Effekseer .efkefc file."
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

Pin down, from the request or by asking (ask only for what changes the output):

- **Effect**: spark, slash, explosion, spell, or a particle cycle, and whether it loops.
- **Cells**: frame count and the engine cell. Read the animations row in
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md) and timing in
  [`craft-animation.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-animation.md). Do not restate their tables.
- **Sheet**: MV-style `img/animations` or a plain strip.
- **Palette**: a short ramp from bright to dark. The effect fades by stepping down that ramp, not by alpha.

Vague request: pick defaults, state them in one line, proceed.

Write `brief.md` beside the spec before the first render, with 2 to 6 done criteria, as
[`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md) describes. A later run that finds it there
reads it and does not ask again. Every review round lists each done criterion as pass or fail.

MZ's native Effekseer format (`.efkefc`) is not a pixel sheet. Say so and offer this skill's cell
sheet instead. Do not write an `.efkefc` file.

## 2. Choose the backend

Same rule as `/pixel-art:sprite`: [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). `native`
is the default.

## 3. Author

Write a short timing table before drawing (key poses, frame count, durations). It is the review
rubric. One procedural `draw(frame)` so the effect grows, bursts, or fades in palette steps, not by
alpha. Hold the impact frame. A worked MV-style spark is
`${CLAUDE_PLUGIN_ROOT}/examples/vfx/spark_mz.py`. Name frames `fx0`, `fx1`, ... and list them under
`animations` with `fps` or `durations_ms`. `sheet.columns` is the engine's column count.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 2
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. Keep the spec and the generator beside the output.
`render.py` writes one GIF per animation.

## 5. Review loop

Read `preview.png` (the Read tool shows a GIF's first frame only, so judge motion from the sheet).
Check the timing table: the silhouette grows or breaks on purpose, the impact frame is held, and
colors stay on the locked palette. Fix the generator, re-render, re-read. Stop when it reads at 1x
or after the user's direction says so; typically 2 to 4 rounds. Name the remaining weaknesses honestly.

## 6. Deliver

Report `sheet.png` at 1x, `sheet.json`, the GIF, and the gallery. For RPG Maker, the sheet belongs
in `img/animations` and the cell grid is the one in `engine-layouts.md`.

## Next

/pixel-art:scene to composite the effect into a scene.

## Gotchas

- `sheet.png` is the engine asset. `preview.png` and the GIF are for review.
- GIF delays are whole hundredths of a second; `render.py` rounds each duration and floors at 20 ms.
- Do not fade with partial alpha. Step down a palette ramp, the same rule as `scene-canvas.md`.
- Effekseer files are out of scope. The delivered asset is the pixel cell sheet.
