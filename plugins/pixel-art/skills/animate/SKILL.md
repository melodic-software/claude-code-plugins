---
description: "Animate pixel-art sprites: idle, walk, run, attack, jump, hurt, death and custom cycles in 1, 4 or 8 directions, exported as engine-ready sprite sheets (RPG Maker MZ, Godot, Aseprite JSON, plain strips) plus looping GIF previews, with no external tools. The model authors pose-parameterised frames, the bundled stdlib renderer writes sheet, frame data and GIFs, and a render-review loop fixes timing and poses. Use when: 'animate this sprite', 'walk cycle', 'sprite sheet', 'idle animation', 'attack animation', 'RPG Maker character sheet', '4-direction walking character', 'make it move'. Not for a single still image (use /pixel-art:sprite) or a composed scene or cutscene (use /pixel-art:scene)."
argument-hint: "<character or sprite spec> <cycles> [directions] [engine]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Author, render, and review pixel-art animation cycles and sprite sheets
---

# Animate

Turn a character (an existing spec, or one described in the request) into animation cycles laid
out the way the target engine expects, and show them moving.

## 1. Brief

Everything in `/pixel-art:sprite` step 1, plus:

- **Cycles** and their purpose: player-controlled actions need responsiveness; enemies and
  cutscene actors can afford anticipation.
- **Directions**: 1 (side-scroller), 4, 8, or isometric.
- **Target layout**: sets frame size, frame count per cycle, direction order, and sheet columns.
  RPG Maker MZ characters, for example, fix 3 patterns x 4 directions at 48x48. Read
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md).

## 2. Plan the cycles

From [`craft-animation.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-animation.md) choose, per cycle,
the key poses, frame count, per-frame duration, and loop direction. Write the plan as a short table
before drawing: it is the review rubric later. Engine layouts override craft defaults (MZ walk is
3 patterns played 0-1-2-1).

## 3. Author

Use a procedural generator for anything past a couple of frames: one `draw(direction, pose)`
function whose parameters (limb angles, step phase, body bob, arm swing, squash) produce each
frame, so every frame stays on-model and a fix lands in every frame at once. A worked example is
`${CLAUDE_PLUGIN_ROOT}/examples/campfire/hero_mz.py` (RPG Maker MZ 4-direction walker); copy it into
the working directory before adapting or running it. Draw one side view and
mirror it for the other only when the design is symmetric; reshade if the light side matters.

Name frames `<cycle>_<direction><index>` or the engine's own names, list them in `sheet.order` in
the engine's order, and declare each cycle under `animations` with `fps` or `durations_ms`.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/render.py" <spec.json> --out <dir> --scale 4
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. `render.py` writes one GIF per animation.

## 5. Review loop

Read `preview.png` (every frame side by side) and each animation GIF (the Read tool shows the first
frame, so judge motion from the sheet). Check against the cycle plan:

- contact and passing poses are distinct and the stride reads in every direction;
- body bob is present and consistent;
- limbs stay separated from the torso (a separate material per limb draws the edge);
- volumes stay constant between frames (no swelling heads or shrinking feet);
- timing: hold impact frames, keep player attacks free of long anticipation.

Fix the generator, re-render, re-read; typically 2 to 4 rounds.

## 6. Deliver

Report `sheet.png` (the engine asset, at 1x), `sheet.json` (frame rects, durations, tags), the GIFs,
and the gallery `index.html`, with the viewing path as in `/pixel-art:sprite`. For an engine
target, name the file-naming rule the engine needs (MZ: `$` prefix for a single-character sheet).

## Next

/pixel-art:scene to put the animated character into a scene or cutscene.

## Gotchas

- GIF delays are whole hundredths of a second; `render.py` rounds each duration and floors at 20 ms.
- The Read tool shows a GIF's first frame only. Review motion from `preview.png`, or from browser
  screenshots when a browser automation tool is present.
- Sub-pixel animation and smear frames depend on palette shades between colours; plan ramps before
  animating.
