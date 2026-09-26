# animation produce: plan

Status: Brief only. Opened by Phase 9 of
[animation-ports/PLAN.md](../animation-ports/PLAN.md); the design session starts here.

## Brief

**Goal.** Ship `/animation:produce`: from a brief and one or more style packs, make pre-production
boards for the user to approve, then a shot list, scenes, rendered frames, a delivered file, and a
review against the pack. Nothing past the storyboard renders until the user approves the boards.

**Decisions already taken (T5, T13 in
[animation-ports/design/design-threads.md](../animation-ports/design/design-threads.md)).**

- The skill is named `produce` (was `film`).
- The artifact sketches in
  [domain-model.md section 2.2](../animation-ports/design/domain-model.md) are the starting shape:
  `brief.md`, `boards/` (style guide, palette, vibe, model and element sheets, storyboard),
  `shots.json`, and `<frames dir>/render.json`, all in one production dir the user names.
  Field-level schemas are decided while building `produce`.
- `shots.json` owns shot cuts: `inkstats.py --cuts` reads it rather than a typed list (one owner
  per value, T16).

**Inputs from animation-ports.**

- `plugins/animation/scripts/render.py`: the render composition root (scene module to frames,
  `--encode` for the delivered file).
- `render.json`: the render manifest written beside the frames
  ([contracts.md section 4](../animation-ports/design/contracts.md)).
- The frame folder contract: one PNG per frame, name index = frame number (same section).

**Out of scope here.** learn-style's `## Next` naming `/animation:produce` lands when the skill
ships (T5), not before.

**Next step.** `/planning:design` for the stage artifacts: field-level schemas, the approval gate,
and how review reads `shots.json` and `render.json`.
