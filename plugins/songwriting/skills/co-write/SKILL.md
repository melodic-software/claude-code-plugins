---
description: "Co-writing sessions under the No-Free-Zone protocol and feedback discipline, the Title Game (chained vowel-cascade title generation), title generation from an idea, and high-volume option dumps for one line or one section, with Pat Pattison's methods. Use when: 'co-write tonight', 'co-write rules', 'no-free-zone', 'Title Game', '10 titles fast', 'title candidates for X', 'give me 30 options for this line', 'brainstorm the whole chorus'. For blank-page/idea/fragment starts use /songwriting:workflow; for rhyme dumps use /songwriting:rhyme."
argument-hint: "[co-write|title-game|title|line-brainstorm|section-brainstorm] [args]"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight. Response Filter

Before emitting titles, line or section option dumps, or co-write feedback, run **§5 Title +
hook** and **§2 Line-writing** of
[response-filter](../../context/pat-pattison/research/response-filter.md) (add **§4 Coaching
posture** when facilitating a live session). Name each box's pass / fail / skip-with-reason (aloud
or in reasoning); correct before emission. Skips are valid; silent skips are not.

§2's **Reference:** line is a load list, not a bibliography: §2 has not run until the files it
names were read this session, at minimum [meter](../../context/pat-pattison/research/meter.md)
and [phrasing](../../context/pat-pattison/research/phrasing.md) before the first candidate, plus
[metaphor](../../context/pat-pattison/research/metaphor.md) when the request asks for an image or
a figure, per [response-filter](../../context/pat-pattison/research/response-filter.md) "§2
Line-writing filter". Naming the §2 boxes without opening those files attests to the filter
instead of applying it, and that is what lets bad lines through: a miscounted stress, or a plain
description labeled a metaphor. Loading is an input, checked in the hard gate below.

When the output is a candidate lyric line about to be shown, cycle §2's boxes inside
[line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md): load it and run the
full cycle per candidate, in its order, naming each pass. On fixed-melody work, show nothing
unless pass 1 (positional fit) comes back clean.
*(Plugin-authored, not Pat Pattison's.)*

## Purpose

The high-volume options are raw material for the writer to choose from, not finished lines.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`; a future
author's method plugs in at `context/<author>/` without changing this skill, the author seam per
the plugin-root `../../README.md` "Method content and the author seam".

## Action Router

`/songwriting:co-write <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches
a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → open the co-write protocol (No-Free-Zone session opener).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `co-write` (default) | co-writing session rules, feedback discipline, No-Free-Zone opener | [co-writing](../../context/pat-pattison/research/co-writing.md), [templates/co-write-session-opener](../../context/pat-pattison/templates/co-write-session-opener.md), [process](../../context/pat-pattison/research/process.md) |
| `title-game` | "Title Game", "Pat's title cascade", "10 titles fast", "vowel-chain titles", co-write warmup | [title-game](../../context/pat-pattison/research/title-game.md), [templates/title-game-prompt](../../context/pat-pattison/templates/title-game-prompt.md), [co-writing](../../context/pat-pattison/research/co-writing.md) |
| `title` | title candidates from an idea, title generation | [hook](../../context/pat-pattison/research/hook.md) "title generation", [idea-to-title](../../context/pat-pattison/research/idea-to-title.md), [templates/title-generation-prompt](../../context/pat-pattison/templates/title-generation-prompt.md) |
| `line-brainstorm` | "30 alternatives for this line", "more end-line words", "lots of swaps". High volume dump for one line | [line-brainstorm](../../context/pat-pattison/research/line-brainstorm.md), [templates/line-brainstorm-prompt](../../context/pat-pattison/templates/line-brainstorm-prompt.md), [mosaic-rhyme](../../context/pat-pattison/research/mosaic-rhyme.md), [meter](../../context/pat-pattison/research/meter.md), [phrasing](../../context/pat-pattison/research/phrasing.md), [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) |
| `section-brainstorm` | "more options for the chorus", "high volume options for this section". Line-brainstorm per line + stability profile + hot-spot map | [line-brainstorm](../../context/pat-pattison/research/line-brainstorm.md) Scope B, [box-model](../../context/pat-pattison/research/box-model.md), [audit-checklist](../../context/pat-pattison/research/audit-checklist.md), [meter](../../context/pat-pattison/research/meter.md), [phrasing](../../context/pat-pattison/research/phrasing.md), [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) |

## Handlers

- Facilitate a co-write as coaching, not monologue, under No-Free-Zone discipline: no idea is
  free, every suggestion earns its place; surface choice points, do not decide for the writers.
- **Line and section brainstorms: the dump goes to the file; the menu goes to chat.** The 30-50+
  columns go to a labeled menu in `variations/` or `worksheets/`, never inline, and the display cap
  never lowers the generated volume. Chat gets 3-4 candidates, each a full section block in context
  with changed lines marked `►`, one labeled block per variation. A response with nothing singable
  in it has not been delivered. See
  [variations](../../context/pat-pattison/research/variations.md) "Presenting the candidates: chat
  vs file".
- **Rubric before the menu:** every candidate cycles all passes of
  [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) before it is shown,
  and pass 1 must come back clean, not merely run. A candidate that you flagged as failing a pass is
  **removed, not disclosed**: showing it with the flag attached is the rule violation, not the
  honest version of it. Present fewer candidates instead.
- **Two rejected executions in a slot stops generation.** *Slot* = the lyric position under
  revision: one line, or one section when the section is being rewritten whole; not the metrical
  or rhyme slot the craft files mean. *Rejection* = the writer declines the batch's execution:
  "none of these", "the idea's right, the lines aren't", or no candidate picked. Picking one and
  asking for a tweak is not a rejection, and rejecting the concept resets the count, because the
  next batch answers a different brief. On the second rejection do not produce a third batch; hand
  the concept over: (1) what the line has to do here, in one sentence; (2) the constraints, as the
  marked positional template plus the section's rhyme and sound obligations; (3) the unused raw
  material, naming images still sitting in the song's `ideation/`; (4) what the two rejected
  batches had in common, named as the failure mode; (5) one question for the writer. No candidate
  lines in that handoff. **Two** is the writer's threshold; do not raise it.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md) "Where
generated work persists", and honor a consuming project's own songwriting layout when it defines
one. Before loading any bundled `templates/<name>.md`, check
`${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` first: a project-level
override wins over the bundled default, first match, per that file's "Template override".

## Boundary. This skill owns line emission, and pays for it

Every other craft skill routes finished lyric lines here, which makes this the one place generic
output escapes into a song. So the gate is an **input** gate: what must exist before lines are
written, not a checklist named afterward.

### Hard gate. Show the artifacts, do not claim them

Before any line is emitted, read [line-emission-gate](../../context/line-emission-gate.md) and
apply every row; its `## Refute, do not review` section is how the skeptic row is dispatched. The
verification command it asks for is
`bash "${CLAUDE_PLUGIN_ROOT}/lib/read-verification.sh" --plugin songwriting --skill co-write`.

### Section mode binds before the line, not after

Verses show; the chorus tells. Verses carry specific situation, image, and action; the chorus makes
the broader statement the verses keep recoloring. Name the mode first, then check each emitted line
against it. A chorus of concrete inventory is verse material in the wrong box, however good the
inventory, and a chorus is sung back, so unsingable length is a defect, not a polish item.

### Mine → adapt → say it aloud

Object-writing output is ore. Pull one image forward and build the line around it; pasting a run of
sensory material into a section relocates the material, it does not use it. Running the first step
and skipping the other two is the failure this section prevents.

1. **Mine**. Take one image, verb, or detail off the page. A finished write is preparation, not
   draft: *"Once you become adept in your object writing, with bushels of sense-bound images
   glittering on the kitchen table, what do you do with them?"* (*Writing Better Lyrics* (2009),
   Chapter 2).
2. **Adapt**. Rewrite the mined image in plain sung English before it enters a slot. In the
   writer's sessions, quoting object-write texture into a lyric slot fails: "hung where it stops
   being anybody's" is ore that reads like a line. Pat's printed demonstration of the crafted shape is the collar:
   "Hot rod hearts and high school rings" replacing "All the things we used to do" (*Writing Better
   Lyrics* (2009), Chapter 2). That every word in it is a common one is this plugin's reading, not
   Pat's claim. **The step itself is plugin-authored:** Pat draws the raw-material-vs-crafted-line
   distinction and prints no translation procedure. See
   [object-writing](../../context/pat-pattison/research/object-writing.md).
3. **Say it aloud**. Would a person say the adapted line, talk-sung? Writer-derived from the same
   sessions; the box lives in
   [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) pass 8. A line that
   fails it goes back to step 2, never forward to a rarer word.

## Related skills

- Sensory raw material before the lines → `/songwriting:object-writing generate`
- Metaphor for a line that needs one → `/songwriting:metaphor`
- Blank page, an idea/seed, or a stuck fragment → `/songwriting:workflow`
- Rhyme partners for the swaps → `/songwriting:rhyme`
- Pre-lock audit of the chosen line/section → `/songwriting:diagnose audit`
- The writer's own register, before any generation → build
  [voiceprint](../../context/pat-pattison/research/voiceprint.md)
- The per-candidate cycle every emitted line clears →
  [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md)
