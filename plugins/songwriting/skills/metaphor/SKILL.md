---
description: "Generate and diagnose metaphor with Pat Pattison's methods — the three types (expressed identity, qualifying, verbal), the three expressed-identity forms, collision drills (noun×verb, noun×noun, adjective×noun), playing in keys (fundamental → diatonic family → collisions), the two metaphor-finder questions, participles, transitive vs intransitive, simile as focus control, and grounded-metaphor diagnosis. Use when: 'I need a metaphor for X', 'generate metaphor options', 'metaphor or simile here', 'this metaphor feels dead', 'my song has no metaphor', 'sustain this image across the song', 'collide these words', 'what else has these characteristics'. For sensory raw material use /songwriting:object-writing; for cliche repair use /songwriting:object-writing cliche."
argument-hint: "[action] [args] (e.g., /songwriting:metaphor collide rain, /songwriting:metaphor keys tide, /songwriting:metaphor simile) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting any metaphor, simile, or collision, run **§7 Image filter** of
[response-filter](../../context/pat-pattison/research/response-filter.md) (add **§2 Line-writing**
when the metaphor arrives inside a finished line). NAME each box's pass / fail / skip-with-reason;
correct before emission. Cliché metaphor families are this skill's dominant failure mode and §7 is
where they are caught.

## Purpose

Figurative language as its own discipline. Metaphor is where a lyric stops describing and starts
seeing one thing as another, and it is the craft dimension most often missing entirely from a draft
rather than merely done badly.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`; a future
author's method plugs in at `context/<author>/` without changing this skill — the author seam per
the plugin-root `../../README.md` "Method content and the author seam".

## Two rules that bind before anything else

**A metaphor must be literally false.** If the two terms are genuinely the same thing, the result
is a definition, not a metaphor. Conflict is the mechanism, not a side effect: put things that do
not belong together in one room and work with the friction.

**Noun+verb beats adjective+noun.** Verbs are the power amplifiers of language — they drive a line
and set it in motion. Collision drills reliably produce better results from noun×verb pairings than
from adjective×noun ones. This is the correction that matters most here, because the default
reach is always for an adjective.

## Action Router

`/songwriting:metaphor <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a
listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → route on context (a subject named → `collide`; an existing metaphor pasted →
`diagnose`).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `collide` (default) | metaphor options for a subject, "I need a metaphor for X", collision drills | [metaphor](../../context/pat-pattison/research/metaphor.md) "three types" + "accident exercises", [templates/metaphor-collision-prompt](../../context/pat-pattison/templates/metaphor-collision-prompt.md) |
| `recipe` | the eight named generation moves run against one subject | [metaphor](../../context/pat-pattison/research/metaphor.md) "Eight named metaphor moves", [templates/metaphor-recipe-prompt](../../context/pat-pattison/templates/metaphor-recipe-prompt.md) |
| `keys` | sustaining an image across a section or song, diatonic vocabulary, "play in the key of X" | [metaphor](../../context/pat-pattison/research/metaphor.md) "Playing in keys" + "Tone center / diatonic vocabulary" |
| `types` | which type is this, the three expressed-identity forms, participles | [metaphor](../../context/pat-pattison/research/metaphor.md) "three metaphor types" + "Expressed identity forms" + "Participles" |
| `simile` | metaphor or simile here, is-vs-like, focus transfer | [metaphor](../../context/pat-pattison/research/metaphor.md) "Simile as focus control" + "Simile versus metaphor" + "energy-blocker model" |
| `diagnose` | is this metaphor grounded, is it dead, is the ambiguity productive or strained | [metaphor](../../context/pat-pattison/research/metaphor.md) "Metaphor diagnosis" + "Grounded metaphor rule" + "Productive ambiguity", [cliche](../../context/pat-pattison/research/cliche.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §7 (+ §2 when the metaphor lands in a line).
- **Options, never a winner.** Surface 6-8 labeled candidates. Label each with its type (expressed
  identity / qualifying / verbal), its linking quality (why it lands), and family distance
  (close / medium / far). The writer picks by emotional intent.
- **Run the two finder questions explicitly, in the output.** What characteristics does this idea
  have? What else has those characteristics? The second question is what releases the options;
  answering it silently and presenting only conclusions skips the generative step.
- **Weight the collisions toward verbs.** In any mixed batch, noun×verb candidates should outnumber
  adjective×noun ones.
- **Take object-writing output as input.** The mined world vocabulary of a song is the raw material
  for playing in keys — a fundamental drawn from the song's own world produces a diatonic family
  the song can actually use.
- For `simile`, apply the focus rule rather than the like/as surface test: metaphor transfers focus
  to the second term and you must commit to it across the song; simile keeps focus on the first
  term, which makes it the right choice for a one-time comparison or a list of them.

## Boundary — what this skill must NOT emit

This skill produces figurative language and judgements about it. It does not write the finished
lyric line the metaphor lives in.

| If you are about to emit | STOP and route to |
| --- | --- |
| A finished verse, chorus, or bridge line | `/songwriting:co-write` line-brainstorm |
| Sensory raw material to collide | `/songwriting:object-writing generate` |
| A rhyme partner for the metaphor's key word | `/songwriting:rhyme` |
| A judgement about where the image belongs structurally | `/songwriting:song-form` |

Routing means invoking that skill, not summarizing what you believe it would say.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Metaphor menus go to the song's
`worksheets/` as a labeled menu, not an inline dump. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Related skills

- Sensory raw material feeding the collisions → `/songwriting:object-writing`
- Cliché taxonomy and redemption → `/songwriting:object-writing cliche`
- Line generation once the metaphor is chosen → `/songwriting:co-write`
- Whole-draft diagnosis, including "this song has no metaphor" → `/songwriting:diagnose`
