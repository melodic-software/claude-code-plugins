---
name: co-write
description: "Run a co-writing session and generate titles and high-volume options with Pat Pattison's methods — the No-Free-Zone co-write protocol and feedback discipline, the Title Game (chained vowel-cascade title generation), title generation from an idea, and high-volume brainstorm dumps for ONE line or ONE section. Use when: 'co-write tonight', 'co-write rules', 'no-free-zone', 'Title Game', '10 titles fast', 'title candidates for X', 'give me 30 options for this line', 'brainstorm the whole chorus'. For blank-page/idea/fragment starts use /songwriting:workflow; for rhyme dumps use /songwriting:rhyme."
argument-hint: "[action] [args] (e.g., /songwriting:co-write, /songwriting:co-write title-game, /songwriting:co-write line-brainstorm \"...\") — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting titles, line/section option dumps, or co-write feedback, run **§5 Title + hook**
and **§2 Line-writing** of [response-filter](../../context/pat-pattison/research/response-filter.md)
(add **§4 Coaching posture** when facilitating a live session). NAME each box's pass / fail /
skip-with-reason (aloud or in reasoning); correct before emission. Skips are valid; silent skips
are not.

## Purpose

Collaborative generation: running a co-write with feedback discipline, generating titles (including
the Title Game), and dumping high-volume labeled options for a single line or section so the writer
has raw material to choose from.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`. A future author's method plugs in
at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:co-write <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → open the co-write protocol (No-Free-Zone session opener).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `co-write` (default) | co-writing session rules, feedback discipline, No-Free-Zone opener | [co-writing](../../context/pat-pattison/research/co-writing.md), [templates/co-write-session-opener](../../context/pat-pattison/templates/co-write-session-opener.md), [process](../../context/pat-pattison/research/process.md) |
| `title-game` | "Title Game", "Pat's title cascade", "10 titles fast", "vowel-chain titles", co-write warmup | [title-game](../../context/pat-pattison/research/title-game.md), [templates/title-game-prompt](../../context/pat-pattison/templates/title-game-prompt.md), [co-writing](../../context/pat-pattison/research/co-writing.md) |
| `title` | title candidates from an idea, title generation | [hook](../../context/pat-pattison/research/hook.md) "title generation", [idea-to-title](../../context/pat-pattison/research/idea-to-title.md), [templates/title-generation-prompt](../../context/pat-pattison/templates/title-generation-prompt.md) |
| `line-brainstorm` | "30 alternatives for this line", "more end-line words", "lots of swaps" — HIGH VOLUME dump for ONE line | [line-brainstorm](../../context/pat-pattison/research/line-brainstorm.md), [templates/line-brainstorm-prompt](../../context/pat-pattison/templates/line-brainstorm-prompt.md), [mosaic-rhyme](../../context/pat-pattison/research/mosaic-rhyme.md) |
| `section-brainstorm` | "more options for the chorus", "high volume options for this section" — line-brainstorm per line + stability profile + hot-spot map | [line-brainstorm](../../context/pat-pattison/research/line-brainstorm.md) Scope B, [box-model](../../context/pat-pattison/research/box-model.md), [audit-checklist](../../context/pat-pattison/research/audit-checklist.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §5 + §2 (+ §4 when facilitating) before output.
- Co-write facilitation is coaching, not monologue: keep the No-Free-Zone discipline — no idea is
  free, every suggestion earns its place; surface choice points, do not decide for the writers.
- Line/section brainstorm writes each option to a labeled menu (per the `variations`/`worksheets`
  persistence convention), not an inline dump.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Line/section brainstorm output goes
to `variations/` or `worksheets/` as a labeled menu (not inline). Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Boundary — this skill owns line emission, and pays for it

Every other craft skill routes finished lyric lines here. That makes this the one place where
generic output escapes into a song, so the gate is an **input** gate: what must exist BEFORE lines
are written, not a checklist named afterward.

### Hard gate — show the artifacts, do not claim them

A box is passed when its output is **visible in this response or on disk at a named path**. A box
named as passed with nothing to show is a failed box. Before emitting lines for a rhymed position:

| Required before emission | What "shown" means |
| --- | --- |
| Sensory raw material exists | a path under the song's `ideation/`, or object-writing output in this response — from `/songwriting:object-writing generate` |
| Rhyme candidates generated | the labeled 8-15 candidate menu across ≥4 stability tiers, including ≥3 mosaic, visible — from `/songwriting:rhyme` |
| Section mode named | stated in this response: does this section SHOW (verse) or TELL (chorus)? |
| Stress map marked | the marked line, not an assertion that it scans — from `/songwriting:meter-prosody` |

Any gate may be skipped. A skip is **named, with its reason, in the output** — that is the "tools,
not rules" stance applied honestly. A silent skip is the failure, and so is listing a box as passed
while its artifact does not exist.

If a gate's input is missing, the correct move is to invoke the skill that produces it, not to
proceed and note the absence. Lines written without their inputs are LLM defaults wearing the
method's vocabulary — which is exactly what the pilot produced, and exactly what the writer
rejected.

### Section mode binds before the line, not after

Verses show; the chorus tells. Verses carry specific situation, image, and action; the chorus makes
the broader statement the verses keep recoloring. Name the mode first, then check each emitted line
against it. A chorus of concrete inventory is verse material in the wrong box, however good the
inventory is — and a chorus is sung back, so unsingable length is a defect, not a polish item.

### Mine, never transcribe

Object-writing output is ore. Pull ONE image forward and build the line around it. Pasting a run of
sensory material into a section is not using the material; it is relocating it.

## Related skills

- Sensory raw material before the lines → `/songwriting:object-writing generate`
- Metaphor for a line that needs one → `/songwriting:metaphor`
- Blank page, an idea/seed, or a stuck fragment → `/songwriting:workflow`
- Rhyme partners for the swaps → `/songwriting:rhyme`
- Pre-lock audit of the chosen line/section → `/songwriting:diagnose audit`
