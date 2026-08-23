---
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

§2's own **Reference:** line is a load list, not a bibliography. §2 has not been run until
[meter](../../context/pat-pattison/research/meter.md) and
[phrasing](../../context/pat-pattison/research/phrasing.md) have been read this session — plus
[metaphor](../../context/pat-pattison/research/metaphor.md) when the request asks for an image or a
figure. Naming the §2 boxes while those files were never opened attests to the filter instead of
applying it, and the attestation is what let the bad lines through: the miscounted stresses and the
plain description labeled a metaphor both came out of a §2 that was named, not loaded. Loading is
therefore an input, checked in the hard gate below, not a step recorded afterward.

And when the output is a candidate LYRIC LINE about to be shown, §2's boxes are cycled inside
[line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) — load it and run the
FULL cycle per candidate, in its order, naming each pass. On fixed-melody work, pass 1 (positional
fit) coming back CLEAN is the condition for showing anything at all.
*(Plugin-authored, writer-derived from the Sofía sessions, 2026-08-12.)*

## Purpose

Collaborative generation: running a co-write with feedback discipline, generating titles (including
the Title Game), and dumping high-volume labeled options for a single line or section so the writer
has raw material to choose from.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`; a future
author's method plugs in at `context/<author>/` without changing this skill — the author seam per
the plugin-root `../../README.md` "Method content and the author seam".

## Action Router

`/songwriting:co-write <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → open the co-write protocol (No-Free-Zone session opener).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `co-write` (default) | co-writing session rules, feedback discipline, No-Free-Zone opener | [co-writing](../../context/pat-pattison/research/co-writing.md), [templates/co-write-session-opener](../../context/pat-pattison/templates/co-write-session-opener.md), [process](../../context/pat-pattison/research/process.md) |
| `title-game` | "Title Game", "Pat's title cascade", "10 titles fast", "vowel-chain titles", co-write warmup | [title-game](../../context/pat-pattison/research/title-game.md), [templates/title-game-prompt](../../context/pat-pattison/templates/title-game-prompt.md), [co-writing](../../context/pat-pattison/research/co-writing.md) |
| `title` | title candidates from an idea, title generation | [hook](../../context/pat-pattison/research/hook.md) "title generation", [idea-to-title](../../context/pat-pattison/research/idea-to-title.md), [templates/title-generation-prompt](../../context/pat-pattison/templates/title-generation-prompt.md) |
| `line-brainstorm` | "30 alternatives for this line", "more end-line words", "lots of swaps" — HIGH VOLUME dump for ONE line | [line-brainstorm](../../context/pat-pattison/research/line-brainstorm.md), [templates/line-brainstorm-prompt](../../context/pat-pattison/templates/line-brainstorm-prompt.md), [mosaic-rhyme](../../context/pat-pattison/research/mosaic-rhyme.md), [meter](../../context/pat-pattison/research/meter.md), [phrasing](../../context/pat-pattison/research/phrasing.md), [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) |
| `section-brainstorm` | "more options for the chorus", "high volume options for this section" — line-brainstorm per line + stability profile + hot-spot map | [line-brainstorm](../../context/pat-pattison/research/line-brainstorm.md) Scope B, [box-model](../../context/pat-pattison/research/box-model.md), [audit-checklist](../../context/pat-pattison/research/audit-checklist.md), [meter](../../context/pat-pattison/research/meter.md), [phrasing](../../context/pat-pattison/research/phrasing.md), [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §5 + §2 (+ §4 when facilitating) before output.
- Co-write facilitation is coaching, not monologue: keep the No-Free-Zone discipline — no idea is
  free, every suggestion earns its place; surface choice points, do not decide for the writers.
- Line/section brainstorm writes each option to a labeled menu (per the `variations`/`worksheets`
  persistence convention), not an inline dump.
- **The DUMP goes to the file; the MENU goes to chat** — 3-4 candidates, each a full section block
  in context with changed lines marked `►`, one labeled block per variation. The 30-50+ columns stay
  in `variations/`/`worksheets/`; the display cap never lowers the generated volume. That is what
  "not an inline dump" means, and a response with nothing singable in it has not been delivered.
  Writer-requested, 2026-08-12 — see
  [variations](../../context/pat-pattison/research/variations.md) "Presenting the candidates —
  chat vs file".
- **Rubric before the menu:** every candidate cycles all passes of
  [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) before it is shown,
  and pass 1 must come back CLEAN, not merely run. A candidate the AI has itself flagged as failing
  a pass is **removed, not disclosed** — showing it with the flag attached is the rule violation,
  not the honest version of it. Present fewer candidates instead.
- **Two rejected executions in a slot stops generation.** *Slot* = the lyric position under
  revision — one line, or one section when the section is being rewritten whole; not the metrical
  or rhyme slot the craft files mean. *Rejection* = the writer declines the batch's EXECUTION:
  "none of these", "the idea's right, the lines aren't", or no candidate picked. Picking one and
  asking for a tweak is not a rejection, and rejecting the CONCEPT resets the count, because the
  next batch answers a different brief. On the second rejection do not produce a third batch; hand
  the concept over — (1) what the line has to do here, in one sentence; (2) the constraints, as the
  marked positional template plus the section's rhyme and sound obligations; (3) the unused raw
  material, naming images still sitting in the song's `ideation/`; (4) what the two rejected
  batches had in common, named as the failure mode; (5) one question for the writer. No candidate
  lines in that handoff. **Two** is the writer's own threshold (Sofía sessions, 2026-08-12); the AI
  does not raise it.

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
named as passed with nothing to show is a failed box. For the source rows, what is shown is a
citation of what the file settled in THIS line — a filename is not an artifact, and neither is the
claim that the method is known. Every row applies before any line is emitted; the rhyme row applies
when the line sits in a rhyme position.

The rows run in the order work actually happens: inputs, then the self-check, then verification.

| Required before emission | What "shown" means |
| --- | --- |
| Writer voiceprint loaded | the four dimensions visible in this response, or the path to the writer's voiceprint file — built per [voiceprint](../../context/pat-pattison/research/voiceprint.md) |
| Craft sources read | `meter.md` and `phrasing.md` read this session, each cited by what it settled for this line — the stress count the line has to hit, the phrase shape it has to keep — not by filename |
| Metaphor source read, when a figure is asked for | `metaphor.md` read, and every figure emitted labeled with its type from Pat's three — Expressed Identity, Qualifying Metaphor, Verbal Metaphor. An unlabeled figure is a plain description until the label is shown |
| Sensory raw material exists | a path under the song's `ideation/`, or object-writing output in this response — from `/songwriting:object-writing generate` |
| Rhyme candidates generated | the labeled 8-15 candidate menu across ≥4 stability tiers, including ≥3 mosaic, visible — from `/songwriting:rhyme`, its search having walked the stressed vowel's coda field and not only the source word's own |
| Section mode named | stated in this response: does this section SHOW (verse) or TELL (chorus)? |
| Positional template or stress map marked | the marked line — or, when a sung melody already exists, the numbered-and-bracketed positional template per [meter](../../context/pat-pattison/research/meter.md) "fitting a replacement line to an already-sung melody" — never an assertion that it scans. From `/songwriting:meter-prosody` |
| Rubric cycled per candidate, pass 1 CLEAN | the pass-by-pass result visible in this response, or at the candidate's named path under the song's `variations/` — per [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md). Pass 1's artifact is the marked template above; on free-melody work the stress map stands in |
| Skeptic refutation returned | the strongest case AGAINST each candidate, visible in this response or at a named path under the song's `variations/` — from a fresh subagent that READ [response-filter](../../context/pat-pattison/research/response-filter.md) §2, the marked map, and [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) at those paths. A line survives when its refutation is stated and judged insufficient; a return holding nothing against anything has shown nothing |

**Every row except the rubric row may be skipped**, and a skip is **named, with its reason, in the
output** — that is the "tools, not rules" stance applied honestly. A silent skip is the failure, and
so is listing a box as passed while its artifact does not exist. Those rows stay skippable because
how much scaffolding a line gets is the writer's craft call, and "There are no rules, only tools."
(*Writing Better Lyrics* (2009), Chapter 18, quoted in
[response-filter](../../context/pat-pattison/research/response-filter.md)) is why. The skeptic row
is in that class deliberately: a refutation pass costs a subagent dispatch, and whether one is
worth spending on a given batch is a judgement, not a rule the writer laid down. Skip it by name
and reason — and expect to be asked why, because self-attestation is what failed.

**The rubric row alone does not carry that clause**, because it is not offered to the writer at all
— it is the AI checking its own output before spending his attention, and he cannot overrule a check
he never saw run. The full statement of the rules behind it is
[line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md)
`## Standing operating rules`; in short, the cycle runs on every candidate every time with no
fatigue exception, and a FAILED pass kills the candidate rather than annotating it. Under load, emit
fewer candidates — not unchecked ones. Passes scoped out by their own headings (no fixed melody, no
rhyme position, no figure, no voiceprint on disk) are declared and stepped past — that is the pass
running, not a skip. This leaves the response-filter's own box-level skip clause untouched: its
§1-§8 boxes remain skippable-with-reason.

If a gate's input is missing, the correct move is to invoke the skill that produces it, not to
proceed and note the absence. Lines written without their inputs are LLM defaults wearing the
method's vocabulary — which is exactly what the pilot produced, and exactly what the writer
rejected. A source row's missing input is a file, so the move is to READ it. Summarizing what a
craft file probably says, or working from a remembered version of it, is the same failure as
skipping the gate with the skip left unnamed.
*(Plugin-authored, writer-derived from the Sofía sessions, 2026-08-12.)*

### Refute, do not review

*(Writer-derived, Sofía sessions, 2026-08-12.)* A self-graded pass is indistinguishable from a real
one when the same context produced both — the pilot ran the response filter as self-attestation and
passed itself. So the skeptic is dispatched to build the case AGAINST each candidate, and it gets
nothing but the candidate batch, the slot's positional template or marked scansion map, and the
source paths to read: not the reasoning that produced the candidates, not which one you prefer.
This is a hard boundary, not a default — the same blind-dispatch mechanic that makes
`/songwriting:object-writing generate`'s fleet work. Its kill rules rank singability and verbosity
ABOVE cleverness: a clever line that cannot be sung in the slot's length is refuted, not merely
ranked lower. The pass runs before the writer sees the batch and settles nothing — the writer's
sing-check is still the last word. Any general subagent honours this today; no agent in this plugin
is a skeptic, and a preloaded-skill skeptic agent is deliberately not shipped here.

### Section mode binds before the line, not after

Verses show; the chorus tells. Verses carry specific situation, image, and action; the chorus makes
the broader statement the verses keep recoloring. Name the mode first, then check each emitted line
against it. A chorus of concrete inventory is verse material in the wrong box, however good the
inventory is — and a chorus is sung back, so unsingable length is a defect, not a polish item.

### Mine → adapt → say it aloud

Object-writing output is ore. Pull ONE image forward and build the line around it. Pasting a run of
sensory material into a section is not using the material; it is relocating it.

Three steps. The pilot ran the first and skipped the other two, and that is the failure the writer
rejected wholesale (Sofía sessions, 2026-08-12).

1. **Mine** — take ONE image, verb, or detail off the page. Pat's own framing of what a finished
   write is for: *"Once you become adept in your object writing, with bushels of sense-bound images
   glittering on the kitchen table, what do you do with them?"* (*Writing Better Lyrics* (2009),
   Chapter 2). Preparation, not draft.
2. **Adapt** — rewrite the mined image in plain sung English BEFORE it enters a slot. Object-write
   prose carries its own texture; quoting that texture into a lyric slot is what failed ("hung
   where it stops being anybody's" is ore that reads like a line). Pat's printed demonstration of
   the crafted shape is the collar: "Hot rod hearts and high school rings" replacing "All the
   things we used to do" (*Writing Better Lyrics* (2009), Chapter 2). That every word in it is a
   common one is this plugin's reading of the example, not a claim Pat makes about it. **The step
   itself is plugin-authored:** Pat draws the raw-material-vs-crafted-line distinction and prints
   no translation procedure — see
   [object-writing](../../context/pat-pattison/research/object-writing.md).
3. **Say it aloud** — would a person SAY the adapted line, talk-sung? Writer-derived from the same
   sessions. The box lives in
   [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) pass 8; a line that
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
