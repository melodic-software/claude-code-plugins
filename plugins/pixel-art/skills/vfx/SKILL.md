---
description: "Pixel-art effects (particles, hit sparks, spells, explosions) as sprite-sheet animations; RPG Maker gets the MV-style img/animations cell sheet. Use when asked for a 'hit spark', 'pixel effect', 'spell animation', 'explosion', 'particle sheet', or 'MZ animation cells'. A character cycle: /pixel-art:animate; a still sprite: /pixel-art:sprite; a cutscene: /pixel-art:scene. Not for Effekseer .efkefc files."
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

Follow [`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md) the same way `/pixel-art:sprite`
does, including the `brief.md` file, the one-line defaults, and the presence-gated
`/planning:interview` offer. The palette is a short ramp from bright to dark: the effect fades by
stepping down that ramp, not by alpha. Then add:

- **Effect**: spark, slash, explosion, spell, or a particle cycle, and whether it loops.
- **Cells**: frame count and the engine cell. Read the animations row in
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md) and timing in
  [`craft-animation.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-animation.md). Do not restate
  their tables.
- **Sheet**: MV-style `img/animations` or a plain strip.

When asked for MZ's native Effekseer format (`.efkefc`), say it is not a pixel sheet and offer
this skill's cell sheet instead. Never write an `.efkefc` file.

## 2. Choose the backend

Read [`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md). Use `native` (the default,
always available) unless the request or `${user_config.backend}` names `aseprite`; when Aseprite is
missing, `backends.py` prints one line and renders with `native`. Pass the choice as
`--backend <name>` in step 4; do not rely on the environment to carry it.

## 3. Author

Before drawing, write a timing table (key poses, frame count, durations); it is the review rubric.
Write one procedural `draw(frame)` that grows, bursts, or fades the effect in palette steps, never
by alpha, and hold the impact frame. A worked MV-style spark is
`${CLAUDE_PLUGIN_ROOT}/examples/vfx/spark_mz.py`. Name frames `fx0`, `fx1`, ..., list them under
`animations` with `fps` or `durations_ms`, and set `sheet.columns` to the engine's column count.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/backends.py" <spec.json> --out <dir> --scale 2
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

`backends.py` writes one GIF per animation. Output location resolves as in `/pixel-art:sprite`.
Keep the spec and the generator beside the output.

## 5. Review loop

Read `preview.png` (the Read tool shows a GIF's first frame only, so judge motion from the sheet).
Check the timing table: the silhouette grows or breaks on purpose, the impact frame is held, and
colors stay on the locked palette. Fix the generator, re-render, re-read. Stop when it reads at 1x
or after the user's direction says so; typically 2 to 4 rounds. Name the remaining weaknesses honestly.

## 6. Deliver

Report `sheet.png` at 1x, `sheet.json`, the GIF, and the gallery. For RPG Maker, the sheet goes in
`img/animations` on the cell grid `engine-layouts.md` gives.

## Next

/pixel-art:scene to composite the effect into a scene.

## Gotchas

- `sheet.png` is the engine asset. `preview.png` and the GIF are for review.
- GIF delays are whole hundredths of a second; `render.py` rounds each duration and floors at 20 ms.
- Do not fade with partial alpha. Step down a palette ramp, the same rule as `scene-canvas.md`.
- Effekseer files are out of scope. The delivered asset is the pixel cell sheet.
