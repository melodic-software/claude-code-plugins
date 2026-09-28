---
description: "Make a film from a brief and one or more style packs: boards for approval, then a shot list, rendered frames, a delivered file, and a review against the pack. Use when: 'produce this film', 'storyboard then render', 'make the boards', 'approve the boards and render', 'shot list for this brief'. Nothing past the storyboard renders before the user approves the boards."
argument-hint: "<production dir> [--pack PACK]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: implement
  summary: Boards for approval, then shots, render, and a pack review
---

# Produce

From a brief and one or more style packs, make pre-production boards, stop for
approval, then a shot list, scenes, rendered frames, a delivered file, and a
review against the pack. The script is
`${CLAUDE_PLUGIN_ROOT}/skills/produce/scripts/produce.py`. Shapes are in
[reference/production.md](reference/production.md). Rendering stays
`${CLAUDE_PLUGIN_ROOT}/scripts/render.py`. Cut times live only in `shots.json`.

Requirements: the plugin README's. `/animation:setup` checks them. Run Python
the way the README says (`uv run --with-requirements`).

## Loop

1. `produce.py init <production dir> --title "<title>" --fps <the pack base_fps>`.
   This writes `brief.md`, the six board files, `scenes/opener.js`, and
   `shots.json`. It does not approve anything.
2. Fill `brief.md` and `boards/` from the brief and the pack: style guide,
   palette, vibe, model sheet, element sheet, storyboard. Replace every stub.
3. Stop. Show the boards to the user. Do not write `boards/APPROVED`, and do
   not render, until the user approves in that file with both of these lines:
   `approved-by: <name>` and `at: <ISO-8601 time>`.
   `produce.py check <production dir>` exits 2 while that file is missing and
   1 while a board is still a stub.
4. After approval, author one scene module per shot (`renderFrame(t)`, ink.js,
   the pack ink color on every stroke). Point each `shots.json` `scene` at its
   file. `produce.py cuts <production dir>` prints the start times.
5. Render only through `produce.py render <production dir> --encode mp4`, which
   refuses when check is not 0. Pass
   `--playwright-core '${user_config.playwright_core}'`.
   Frames land in `<production dir>/frames` with `render.json`. The encoded
   file is `frames.mp4` beside that directory.
6. Review with `produce.py review <production dir> --pack <pack dir>`.
   It runs inkstats with `--shots <production dir>/shots.json` and refuses a
   typed `--cuts` list beside that file. Read frames at 1:1 beside the
   storyboard. A numeric pass that does not look like the pack is a fail.

Repeat steps 4 to 6 until the review passes. Tune the scenes, never the pack,
unless the user asked to change the pack.

## Next

/animation:learn-style <rotoscope work dir> <pack dir>

## Gotchas

- Do not write `boards/APPROVED` yourself. The user does. A render that skips
  the file is a broken run even if frames exist.
- `shots.json` is the only cut list. Pass `--shots`, not a typed `--cuts` list,
  for a film this skill made.
- `produce.py render --dry-run` prints the render command and does not draw.
  The delivered film comes from a real render.
- The opener scene is a placeholder. Replace it before calling the film done.
