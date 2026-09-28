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

1. `produce.py init <production dir> --title "<title>" --style <pack>`.
   This writes `brief.md`, `boards/storyboard.md`, and `shots.json`. It does
   not approve anything.
2. Fill the brief and the storyboard from the brief and the pack. Show the
   boards to the user.
3. Stop. `produce.py gate <production dir>` exits 2, and says the boards are
   not approved, until the user writes a non-empty `boards/APPROVED`. Do not
   render before that. Do not write `boards/APPROVED` yourself.
4. After approval, add shots to `shots.json` (`t0` increasing from 0, `scene`
   a `.js` path, `title` set) and write each scene module (`renderFrame(t)`,
   ink.js, the pack ink color). `produce.py cuts <production dir>` prints the
   interior starts.
5. Render each scene with
   `${CLAUDE_PLUGIN_ROOT}/scripts/render.py <scene.js> <frames dir> --fps <shots.json fps> --encode mp4 --playwright-core '${user_config.playwright_core}'`.
   Frames land beside `render.json`.
6. Review with
   `${CLAUDE_PLUGIN_ROOT}/scripts/inkstats.py <film> --shots <production dir>/shots.json --pack <pack dir>`.
   `--shots` reads the cuts. Do not also pass `--cuts`. Read frames at 1:1
   beside the storyboard. A numeric pass that does not look like the pack is a
   fail.

`produce.py check <production dir>` prints `boards` or `approved`.

## Next

/animation:learn-style <rotoscope work dir> <pack dir>

## Gotchas

- `boards/APPROVED` is the user's file. An empty file is not approval.
- `inkstats.py --cuts` and `--shots` together are refused. A production passes
  `--shots`.
- Bands are in pixels. Render at the pack's frame size.
