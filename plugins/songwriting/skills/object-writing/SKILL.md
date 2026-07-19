---
name: object-writing
description: "Generate raw sensory material and images with Pat Pattison's methods — object writing (sense-bound, 90-second timed dives, Rusty's-collar/Kami-kazi), metaphor (3 types, 8 recipes, collision drills, transitive/intransitive), cliche taxonomy + redemption, and point of view (camera distance, pronoun consistency). Use when: 'object writing', 'make this less abstract', 'show don't tell', '90-second writing prompt', 'I need a metaphor for X', 'generate metaphor options', 'this line sounds cliched', 'who is speaking in this lyric'. For rhyme use /songwriting:rhyme; for daily curriculum use /songwriting:practice."
argument-hint: "[action] [args] (e.g., /songwriting:object-writing, /songwriting:object-writing metaphor-recipe trust) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting any image, metaphor, sensory prompt, or rewrite, run **§7 Image filter (object
writing + metaphor)** of [response-filter](../../context/pat-pattison/research/response-filter.md)
(add **§2 Line-writing** when producing lines). NAME each box's pass / fail / skip-with-reason;
correct before emission. Skips are valid; silent skips are not — abstract telling and cliche
imagery are the defaults this filter catches.

## Purpose

Sense-bound raw material and figurative language: object writing, metaphor/simile, cliche repair,
and point of view. This is the "showing, not telling" engine — the source of concrete detail the
other skills shape.

Method content is Pat Pattison's, under `context/pat-pattison/`. A future author's imagery method
plugs in at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:object-writing <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → issue one usable timed object-writing prompt immediately (do not assign a curriculum).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `object-writing` (default) | sensory writing, showing instead of telling, raw material | [object-writing](../../context/pat-pattison/research/object-writing.md), [templates/object-writing-prompt](../../context/pat-pattison/templates/object-writing-prompt.md) |
| `metaphor` | metaphor, simile, collision drills, linking qualities, productive ambiguity, is-vs-like | [metaphor](../../context/pat-pattison/research/metaphor.md), [templates/metaphor-collision-prompt](../../context/pat-pattison/templates/metaphor-collision-prompt.md) |
| `metaphor-recipe` | 8 named metaphor moves to generate options from a subject | [metaphor](../../context/pat-pattison/research/metaphor.md) "8 recipes", [templates/metaphor-recipe-prompt](../../context/pat-pattison/templates/metaphor-recipe-prompt.md) |
| `cliche` | cliche phrase, cliche image, stale metaphor, cliche rhyme | [cliche](../../context/pat-pattison/research/cliche.md), [worksheets](../../context/pat-pattison/research/worksheets.md), [metaphor](../../context/pat-pattison/research/metaphor.md) |
| `pov` | first/second/third person, direct address, dialogue, pronoun consistency, camera distance | [point-of-view](../../context/pat-pattison/research/point-of-view.md) |
| `worksheet` | broader sense-bound worksheets (not rhyme worksheets) | [worksheets](../../context/pat-pattison/research/worksheets.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §7 (+ §2 when producing lines) before output.
- If the user asks for a prompt, generate one usable timed exercise immediately (default
  90 seconds). Do not assign the full curriculum unless asked — that is `/songwriting:practice`.
- Keep object-writing sense-bound and personal; its job is to reveal specific, sensory detail, not
  to produce finished lines.
- For metaphor, name the type and recipe used; offer options, not a single winner.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Related skills

- Rhyme choice and rhyme cliche → `/songwriting:rhyme`
- Daily practice curriculum and numbered exercises → `/songwriting:practice`
- Whole-draft diagnosis (where images fail in context) → `/songwriting:diagnose`
