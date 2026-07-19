---
name: practice
description: "Build a songwriting practice habit with Pat Pattison's curriculum — the daily object-writing/craft routine and numbered exercises drawn from all four books (Essential Guide to Lyric Form and Structure structural exercises, Songwriting Without Boundaries 56-day curriculum, Essential Guide to Rhyming worksheets). Use when: 'daily practice plan', 'build a writing habit', 'give me a 90-second writing prompt', 'run me a numbered exercise', 'exercise 4.6', 'daily craft prompt'. For a one-off object-writing prompt use /songwriting:object-writing."
argument-hint: "[action] [args] (e.g., /songwriting:practice, /songwriting:practice exercise 4.6) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

When a practice run produces sample lines, images, or rhymes, run the applicable section of
[response-filter](../../context/pat-pattison/research/response-filter.md) (§1 rhyme, §2 line,
§7 image) before emitting them. NAME each box's pass / fail / skip-with-reason; correct before
emission. Skips are valid; silent skips are not. Prompt-only runs (assigning an exercise) need no
filter pass.

## Purpose

The habit layer: a daily craft routine and a numbered-exercise index across all four books, so a
writer can build and sustain practice. This skill hands out prompts and curricula; the craft skills
do the in-the-moment coaching on the output.

Method content is Pat Pattison's, under `context/pat-pattison/`. A future author's curriculum plugs
in at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:practice <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → issue one daily craft prompt immediately (default a 90-second object-writing dive).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `daily` (default) | a daily craft prompt or practice curriculum | [daily-practice](../../context/pat-pattison/research/daily-practice.md), [templates/object-writing-prompt](../../context/pat-pattison/templates/object-writing-prompt.md), [templates/metaphor-collision-prompt](../../context/pat-pattison/templates/metaphor-collision-prompt.md) |
| `exercise` | a numbered exercise from any of the four books (structural / 56-day / rhyme worksheets) | [exercises](../../context/pat-pattison/research/exercises.md) |

## Handlers

- **Pre-flight when producing sample output:** run the applicable response-filter section; a
  prompt-only (assign-an-exercise) run needs no filter pass.
- Give one usable prompt or a bounded sequence — do not assign the full curriculum unless asked.
- Practice output persists per the artifact convention (`songwriting/practice/<YYYY>/<date>.md`).

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md) (daily practice
to `songwriting/practice/<YYYY>/<date>.md`), and honor a consuming project's own layout when it
defines one. Before loading any bundled `templates/<name>.md`, check
`${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` first — a project-level override
wins over the bundled default.

## Related skills

- A single in-session object-writing or metaphor prompt → `/songwriting:object-writing`
- Rhyme worksheets specifically → `/songwriting:rhyme worksheet`
