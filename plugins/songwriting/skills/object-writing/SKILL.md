---
name: object-writing
description: "Generate raw sensory material with Pat Pattison's methods — object writing (sense-bound, timed dives, the pivot chain, the seven-channel sense inventory, Rusty's-collar/Kami-kazi), an agent that performs the write itself, cliche taxonomy + redemption, and point of view (camera distance, pronoun consistency). Use when: 'object writing', 'you do the object writing', 'make this less abstract', 'show don't tell', '90-second writing prompt', 'this line sounds cliched', 'who is speaking in this lyric'. For metaphor use /songwriting:metaphor; for rhyme use /songwriting:rhyme; for daily curriculum use /songwriting:practice."
argument-hint: "[action] [args] (e.g., /songwriting:object-writing, /songwriting:object-writing generate rain) — full actions in body"
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

Sense-bound raw material: object writing, cliche repair, and point of view. This is the "showing,
not telling" engine — the source of concrete detail the other skills shape. Metaphor is its own
discipline and its own skill (`/songwriting:metaphor`); this skill feeds it.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`. A future author's imagery method
plugs in at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:object-writing <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → issue one usable timed object-writing prompt immediately (do not assign a curriculum).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `object-writing` (default) | sensory writing, showing instead of telling, raw material | [object-writing](../../context/pat-pattison/research/object-writing.md), [templates/object-writing-prompt](../../context/pat-pattison/templates/object-writing-prompt.md) |
| `generate` | **YOU** do the object writing — "you write it", "do the object writing", "I don't want to write it", or any request for raw sensory material the writer is not going to produce | dispatch the `object-writer` agent — see below |
| `cliche` | cliche phrase, cliche image, stale metaphor, cliche rhyme | [cliche](../../context/pat-pattison/research/cliche.md), [worksheets](../../context/pat-pattison/research/worksheets.md), [metaphor](../../context/pat-pattison/research/metaphor.md) |
| `pov` | first/second/third person, direct address, dialogue, pronoun consistency, camera distance | [point-of-view](../../context/pat-pattison/research/point-of-view.md) |
| `worksheet` | broader sense-bound worksheets (not rhyme worksheets) | [worksheets](../../context/pat-pattison/research/worksheets.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §7 (+ §2 when producing lines) before output.
- If the user asks for a prompt, generate one usable timed exercise immediately (default
  90 seconds). Do not assign the full curriculum unless asked — that is `/songwriting:practice`.
- Keep object-writing sense-bound and personal; its job is to reveal specific, sensory detail, not
  to produce finished lines.
- A metaphor request routes to `/songwriting:metaphor`. Sensory material mined here is that skill's
  input — hand over the material, do not generate the metaphor here.

## `generate` — dispatch, never write it inline

**Who writes matters more than what is loaded.** Reading this skill's files and then writing a
dive in the main thread reliably produces a static scene description, because the discipline was
read rather than carried. Dispatch the `object-writer` agent, whose system prompt IS the
discipline.

Dispatch rules:

1. **One agent per seed**, all in a single message so they run concurrently. Two agents on the same
   seed is a valid and useful play — same board, different dives.
2. **Give each agent nothing but the seed, the timer, the category, and its own output path.** Not
   the song, not the title, not the draft, not the diagnosis, not the other agents' seeds. The
   isolation is the mechanism; briefing an agent on the song destroys the divergence it exists to
   produce. This is a hard boundary, not a default.
3. **Each agent writes to its own file** under the song's `ideation/` (per
   [artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md)) and returns
   a path plus a sense-inventory summary. Never ask an agent to return the write in a message.
4. **Grade coverage on return**, then mine. Read each file, honor thin-channel reports rather than
   overruling them, and pull individual images forward. Mining stays here because you hold the song
   context the writers deliberately lack.
5. **For rounds:** name what made the strongest write of a round work, then carry that as the
   standard into the next round's dispatch. The bar escalates; rounds are not independent repeats.

**Never transcribe a write into lines.** The whole page is ore. Pat's discipline is to pull one
image out of it — moving a dive wholesale into a section is the failure this action exists to
prevent, not its purpose.

Nothing else in this skill dispatches agents. Metaphor generation is
`/songwriting:metaphor`; line-writing is not this skill's job at all (see boundaries below).

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Boundary — what this skill must NOT emit

This skill produces raw sensory material and figurative language. It does **not** produce finished
lyric lines, and being mid-conversation about a song does not authorize it to.

| If you are about to emit | STOP and route to |
| --- | --- |
| A finished verse, chorus, or bridge line | `/songwriting:co-write` line-brainstorm |
| A rhyme partner or rhyme list | `/songwriting:rhyme` |
| A section rewrite, or a judgement about where a section's material belongs | `/songwriting:song-form` |
| A scansion or stress-map claim | `/songwriting:meter-prosody` |

Routing means invoking that skill, not summarizing what you believe it would say. Emitting a lyric
line from here is the specific failure the boundary exists to catch: the generative discipline
lives in the skill that owns it, and material that arrives without passing through that skill
arrives as an LLM default wearing the vocabulary.

## Related skills

- Metaphor generation and diagnosis → `/songwriting:metaphor`
- Rhyme choice and rhyme cliche → `/songwriting:rhyme`
- Daily practice curriculum and numbered exercises → `/songwriting:practice`
- Whole-draft diagnosis (where images fail in context) → `/songwriting:diagnose`
