---
name: song-form
description: "Build and balance song structure with Pat Pattison's methods — section identification (verse/chorus/bridge/refrain), forms (AABA, verse/chorus, verse/refrain), the candy-bar rewrite, hook placement and hot spots, repetition/repainting (You-I-We, Past-Present-Future, hidden questions/commands), verse development and the box model, bridge writing, and Essential Guide to Lyric Form and Structure worked examples. Use when: 'is this verse/chorus or AABA', 'where should the title go', 'my chorus does not land', 'my second verse repeats the first', 'what goes in verse 2/3', 'write me a bridge', 'do I need a bridge'. For stability/scansion use /songwriting:meter-prosody."
argument-hint: "[action] [args] (e.g., /songwriting:song-form, /songwriting:song-form bridge, /songwriting:song-form box-model) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting a form recommendation, section rewrite, hook placement, or bridge, run
**§6 Form filter** of [response-filter](../../context/pat-pattison/research/response-filter.md)
(add **§5 Title + hook** for hook/title placement). NAME each box's pass / fail / skip-with-reason;
correct before emission. Skips are valid; silent skips are not.

## Purpose

The architecture layer: how sections are identified, contrasted, balanced, and repeated so the form
serves the song. Covers form selection, hook/title placement, repetition and repainting, verse
division of labor (box model), verse development, and bridges.

Method content is Pat Pattison's, under `context/pat-pattison/`. A future author's method plugs in
at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:song-form <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → route on context (a structural question → `form`; "write me a bridge" → `bridge`).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `form` (default) | verse/chorus/bridge balance, section contrast, candy-bar rewrite | [form](../../context/pat-pattison/research/form.md), [section-building](../../context/pat-pattison/research/section-building.md), [song-forms](../../context/pat-pattison/research/song-forms.md) |
| `song-forms` | AABA, verse/chorus, verse/refrain, bridge validity, four-times-a-lot / third-system risk, 1991 worked examples | [song-forms](../../context/pat-pattison/research/song-forms.md), [song-forms-examples](../../context/pat-pattison/research/song-forms-examples.md), [repetition](../../context/pat-pattison/research/repetition.md) |
| `hook` | title placement, hook hot spots (section + phrase level), hook rhythm, targeting | [hook](../../context/pat-pattison/research/hook.md), [form](../../context/pat-pattison/research/form.md) |
| `repetition` | chorus repetition, repainting, stagnant repeats, You-I-We, Past-Present-Future, hidden Q/cmd | [repetition](../../context/pat-pattison/research/repetition.md), [box-model](../../context/pat-pattison/research/box-model.md), [song-forms](../../context/pat-pattison/research/song-forms.md) |
| `verse` | second-verse problems, travelogues, verse development, power positions, trigger lines | [verse-development](../../context/pat-pattison/research/verse-development.md), [box-model](../../context/pat-pattison/research/box-model.md), [repetition](../../context/pat-pattison/research/repetition.md) |
| `box-model` | verse division of labor, second-verse stagnation, what goes in verse 2 / 3 | [box-model](../../context/pat-pattison/research/box-model.md), [verse-development](../../context/pat-pattison/research/verse-development.md) |
| `bridge` | "write me a bridge", "do I need a bridge", bridge as restatement, three bridge functions, AABA homecoming | [bridge](../../context/pat-pattison/research/bridge.md), [templates/bridge-writing-prompt](../../context/pat-pattison/templates/bridge-writing-prompt.md), [form](../../context/pat-pattison/research/form.md), [song-forms](../../context/pat-pattison/research/song-forms.md) |
| `section-building` | building or contrasting a single section from the ground up | [section-building](../../context/pat-pattison/research/section-building.md), [form](../../context/pat-pattison/research/form.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §6 (+ §5 for hook/title) before output.
- Name the form and what each section is DOING; recommend the smallest structural change that fixes
  the problem, not a wholesale rewrite.
- Repetition is repainting, not stagnation — a repeated chorus should mean something new by its
  surrounding context each time.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Related skills

- Stability and scansion of the sections → `/songwriting:meter-prosody`
- Rhyme within sections → `/songwriting:rhyme`
- Whole-draft diagnosis → `/songwriting:diagnosis`
