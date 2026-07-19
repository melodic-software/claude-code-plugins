---
name: meter-prosody
description: "Scan lines and make structure serve meaning with Pat Pattison's methods — meter (scansion, Paradigms I/II/III, Pentad, Goldilocks, the 'into' rule, In Memoriam quatrain, pitch-stress), prosody (motion-emotion, greedy spots, tone-of-voice, three phrasing types), section stability (stable/unstable scan), and lyric-melody alignment. Use when: 'scan this line', 'can this be common meter', 'is this verse stable or unstable', 'my words don't fit the music', 'greedy spot in line 2', 'set lyrics to this tune', 'does my song feel right'. For song sections/form use /songwriting:song-form; for rhyme use /songwriting:rhyme."
argument-hint: "[action] [args] (e.g., /songwriting:meter-prosody meter \"...\", /songwriting:meter-prosody stability chorus) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting a scansion verdict, stability call, phrasing judgement, or any rewrite, run
**§6 Form filter** of [response-filter](../../context/pat-pattison/research/response-filter.md)
(add **§2 Line-writing** when producing lines). NAME each box's pass / fail / skip-with-reason;
correct before emission. Skips are valid; silent skips are not.

## Purpose

The sound-and-motion layer: whether the number, placement, and stress of syllables — and the
stability of each section — support the meaning and emotion. Covers scansion, prosody, phrasing,
stable/unstable analysis, and fitting lyric to melody.

Method content is Pat Pattison's, under `context/pat-pattison/`. A future author's method plugs in
at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:meter-prosody <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → route on context (a pasted line → `meter`; a "does this feel right" → `stability`).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `meter` | scansion, tetrameter, common meter, stress, Paradigms, Pentad, Goldilocks, 'into' rule, In Memoriam, pitch-stress | [meter](../../context/pat-pattison/research/meter.md) |
| `prosody` | whether structure supports meaning, motion, greedy spots, tone-of-voice | [prosody](../../context/pat-pattison/research/prosody.md), [meter](../../context/pat-pattison/research/meter.md), [stable-unstable-meta](../../context/pat-pattison/research/stable-unstable-meta.md) |
| `phrasing` | the three phrasing types, front/back-heavy lines, breath and pacing | [phrasing](../../context/pat-pattison/research/phrasing.md), [meter](../../context/pat-pattison/research/meter.md), [prosody](../../context/pat-pattison/research/prosody.md) |
| `stability` | section-level stable/unstable scan, "does my song feel right" | [stable-unstable-meta](../../context/pat-pattison/research/stable-unstable-meta.md) |
| `align-melody` | lyric-melody mismatch, setting words to a tune, roadmap problems, greedy spots | [lyric-melodic-roadmaps](../../context/pat-pattison/research/lyric-melodic-roadmaps.md), [phrasing](../../context/pat-pattison/research/phrasing.md), [prosody](../../context/pat-pattison/research/prosody.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §6 (+ §2 when producing lines) before output.
- Scan concretely: mark stresses, name the paradigm, and say what the meter does FOR the meaning —
  not scansion for its own sake.
- Stability is a tool, not a verdict: name whether a section reads stable or unstable and whether
  that serves the section's job; the writer chooses.
- Greedy spots (too many syllables for the melodic slot) route through `align-melody` + `prosody`.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Related skills

- Section identification, form-fit, hook placement → `/songwriting:song-form`
- Rhyme position and stability → `/songwriting:rhyme strategy`
- Whole-draft diagnosis → `/songwriting:diagnose`
