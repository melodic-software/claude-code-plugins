---
description: "Animate pixel-art sprites: idle, walk, run, attack, jump, hurt, death and custom cycles in 1, 4 or 8 directions, exported as sprite sheets laid out for the target engine (RPG Maker MZ, Godot, PICO-8, plain strips) with Aseprite-shaped frame data and looping GIF previews, with no external tools. The model authors pose-parameterised frames, the bundled stdlib renderer writes sheet, frame data and GIFs, and a render-review loop fixes timing and poses. Use when: 'animate this sprite', 'walk cycle', 'sprite sheet', 'idle animation', 'attack animation', 'RPG Maker character sheet', '4-direction walking character', 'make this sprite move'. Not for a single still image (use /pixel-art:sprite), a composed scene or cutscene (use /pixel-art:scene), or hand-drawn or ink-style animation and general video output."
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

Follow [`brief.md`](${CLAUDE_PLUGIN_ROOT}/reference/brief.md) the same way `/pixel-art:sprite`
does, including the `brief.md` file, the one-line defaults, and the presence-gated
`/planning:interview` offer. Then add:

- **Cycles** and their purpose: player-controlled actions need responsiveness; enemies and
  cutscene actors can afford anticipation.
- **Directions**: 1 (side-scroller), 4, 8, or isometric.
- **Target layout**: sets frame size, frame count per cycle, direction order, and sheet columns.
  RPG Maker MZ characters, for example, fix 3 patterns x 4 directions at 48x48. Read
  [`engine-layouts.md`](${CLAUDE_PLUGIN_ROOT}/reference/engine-layouts.md).

When the character is an existing spec that already has `brief.md` beside it, read that file and
extend it with cycles, directions, and layout. Do not re-ask fields it already answers. Write the
extended brief beside this spec before the first render.

## 2. Plan the cycles

From [`craft-animation.md`](${CLAUDE_PLUGIN_ROOT}/reference/craft-animation.md) choose, per cycle,
the key poses, frame count, per-frame duration, and loop direction. Write the plan as a short table
before drawing: it is the review rubric later. Engine layouts override craft defaults (MZ walk is
3 patterns played 0-1-2-1).

## 3. Author

Use a procedural generator for anything past a couple of frames: one `draw(direction, pose)`
function whose parameters (limb angles, step phase, body bob, arm swing, squash) produce each
frame, so every frame stays on-model and a fix lands in every frame at once. For a humanoid
walker, start from `${CLAUDE_PLUGIN_ROOT}/scripts/kit.py` and adapt it: a proportion preset
(`chibi`, `standard`, `tall`), a head shape, a hair shape, material ramps, and an `extra`
callback for clothing or props. `${CLAUDE_PLUGIN_ROOT}/examples/walker/blacksmith.py` is a
4-direction walker built that way. `${CLAUDE_PLUGIN_ROOT}/examples/campfire/hero_mz.py` is an
earlier hand-written MZ sheet; copy either example into the working directory before running it, with `kit.py` beside `blacksmith.py`.
Draw one side view and mirror it for the other only when the design is symmetric; the kit shades
after the mirror so the light stays top-left.

A PNG from another backend is snapped with `render.py --snap` before its rows enter the spec
([`backends.md`](${CLAUDE_PLUGIN_ROOT}/reference/backends.md)). Palette presets and project palette
files are the same strings `sprite` uses ([`palettes/README.md`](${CLAUDE_PLUGIN_ROOT}/palettes/README.md)).

Name frames `<cycle>_<direction><index>` or the engine's own names, list them in `sheet.order` in
the engine's order, and declare each cycle under `animations` with `fps` or `durations_ms`.

## 4. Render

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/backends.py" <spec.json> --out <dir> --scale 4
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/gallery.py" <dir>
```

Output location resolves as in `/pixel-art:sprite`. `backends.py` follows the same backend rule as
`/pixel-art:sprite` (native unless `${user_config.backend}` or `--backend` says otherwise, and no
`--confirm` until the user accepts a paid call). It writes one GIF per animation.

## 5. Review loop

Read `preview.png` (every frame side by side) and each animation GIF (the Read tool shows the first
frame, so judge motion from the sheet). Every round, list each done criterion in `brief.md` as
pass or fail with a one-line reason. Also check the cycle plan:

- contact and passing poses are distinct and the stride reads in every direction;
- body bob is present and consistent;
- limbs stay separated from the torso (a separate material per limb draws the edge);
- volumes stay constant between frames (no swelling heads or shrinking feet);
- timing: hold impact frames, keep player attacks free of long anticipation.

Fix the generator, re-render, re-read. Stop when every done criterion passes, or after the round
budget (typically 2 to 4) with the failing criteria named.

## 6. Deliver

Report `sheet.png` (the engine asset, at 1x), `sheet.json` (frame rects, durations, tags), the GIFs,
and the gallery `index.html`, with the viewing path as in `/pixel-art:sprite`. For an engine
target, deliver the sheet under the filename the engine needs: for an RPG Maker MZ single
character, copy `sheet.png` to `$<name>.png` (without the `$` prefix MZ reads the image as an
eight-character sheet).

## Next

/pixel-art:scene to put the animated character into a scene or cutscene.

## Gotchas

- GIF delays are whole hundredths of a second; `render.py` rounds each duration and floors at 20 ms.
- The Read tool shows a GIF's first frame only. Review motion from `preview.png`, or from browser
  screenshots when a browser automation tool is present.
- Sub-pixel animation and smear frames depend on palette shades between colors; plan ramps before
  animating.
