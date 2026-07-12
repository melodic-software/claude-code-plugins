---
name: workflow
description: "Start-here situation router for songwriting with Pat Pattison's methods — picks the scenario for a blank page, an idea/seed, a stuck fragment, a co-write, a diagnose-only pass, or a daily habit, and runs step-by-step coaching dialog. Also applies Pat's response filter to AI-generated material and points to going-deeper resources (Coursera / Berklee / columns / podcasts). Use when: 'I want to write a new song', 'I have nothing — just want to write', 'I have an image but no title', 'this fragment is stuck', 'walk me through writing this', 'guide me', 'where do I start', 'review the rhyme list this AI gave me', 'how do I go deeper'. Craft-specific requests route to the concern skills below."
argument-hint: "[action] [args] (e.g., /songwriting:workflow, /songwriting:workflow coach, /songwriting:workflow brainstorm) — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Every craft output in this plugin runs the applicable section of
[response-filter](../../context/pat-pattison/research/response-filter.md) before emission — the gate
that activates the discipline. When this skill coaches or produces material directly, run **§4
Coaching posture** (and the output-type section for anything emitted). NAME each box's pass / fail /
skip-with-reason; correct before emission. Skips are valid; silent skips are not.

## Purpose

The orchestrator and front door. Turn a situation ("I have half a song", "blank page", "co-write
tonight") into the right scenario and the right craft skill, and run guided step-by-step dialog when
the writer wants to be walked through it. When the user names a craft term (rhyme, meter, form,
image), route straight to that concern skill.

Method content is Pat Pattison's, under `context/pat-pattison/`. A future author's process plugs in
at `context/<author>/` without changing this skill.

## Concern skills — route craft-term requests here

| The user wants | Skill |
| --- | --- |
| rhyme choice, rhyme types, mosaic, rhyme worksheet, syllable/Datamuse lookup | `/songwriting:rhyme` |
| object writing, metaphor, cliche repair, point of view | `/songwriting:object-writing` |
| scansion, meter, prosody, phrasing, stability, lyric-melody fit | `/songwriting:meter-prosody` |
| form, song forms, hook, repetition, verse, bridge, box model | `/songwriting:song-form` |
| co-write protocol, Title Game, titles, high-volume line/section dumps | `/songwriting:co-write` |
| diagnose a draft, demo review, pre-lock audit, variations, rewrite | `/songwriting:diagnosis` |
| daily practice curriculum, numbered exercises | `/songwriting:daily-practice` |
| Suno v5.5 prompt formatting (separate capability) | `/songwriting:suno` |

## Action Router

`/songwriting:workflow <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → route on conversation context (pick the scenario the situation describes).

| Action | Use when the user describes | Load |
| --- | --- | --- |
| `workflow` (default) | brand-new song / existing-song revision / from a title / to a melody / co-write / diagnose-only / daily habit / brainstorm / idea / fragment / demo | [workflows](../../context/pat-pattison/research/workflows.md) — picks the scenario chain (11 scenarios) |
| `coach` | "guide me", "walk me through", "help me think", "what next" — dynamic step-by-step dialog | [coaching-protocol](../../context/pat-pattison/research/coaching-protocol.md), [workflows](../../context/pat-pattison/research/workflows.md) |
| `brainstorm` | "blank page", "no idea", "starting cold", "give me anything" | [brainstorm](../../context/pat-pattison/research/brainstorm.md), [templates/brainstorm-opener](../../context/pat-pattison/templates/brainstorm-opener.md) |
| `idea` | "I have an idea / image / phrase / feeling but no title" | [idea-to-title](../../context/pat-pattison/research/idea-to-title.md), [templates/idea-to-title-prompt](../../context/pat-pattison/templates/idea-to-title-prompt.md), [object-writing](../../context/pat-pattison/research/object-writing.md) |
| `fragment` | "I have this line / hook / half-verse — won't grow" | [fragment-development](../../context/pat-pattison/research/fragment-development.md), [templates/fragment-development-prompt](../../context/pat-pattison/templates/fragment-development-prompt.md), [verse-development](../../context/pat-pattison/research/verse-development.md) |
| `filter` | "apply Pat's filter to this", "review my AI-generated rhyme list", "is this passing the discipline" — diagnostic mode | [response-filter](../../context/pat-pattison/research/response-filter.md) |
| `beyond-books` | Coursera / Berklee Online / patpattison.com columns / podcasts / workshops, "how do I go deeper" | [beyond-books](../../context/pat-pattison/research/beyond-books.md) |

Full scenario + craft-term routing tables and the Quick Decision Guide (35+ user-question → route
mappings across all skills) live in
[action-routing](../../context/pat-pattison/research/action-routing.md) — load it when routing is
ambiguous or when surfacing the menu.

## Songwriter Workflow Scenarios

11 scenarios via `workflow` (chains in
[workflows](../../context/pat-pattison/research/workflows.md)):

1. Brand new song from scratch
2. Existing song revision
3. Writing from a title
4. Writing to an existing melody
5. Co-write session start
6. Diagnose without rewrite
7. Build a daily practice habit
8. Pure brainstorm (no seed yet)
9. Idea / seed but no title
10. Fragment in hand
11. Demo at any stage

Each scenario lists which context files to load in what order and which concern skill owns the deep
dive. Every scenario routes through
[response-filter](../../context/pat-pattison/research/response-filter.md) at emission time.

## Handlers

- If the user describes a SITUATION (not a craft term), route via `workflow` to the matching
  scenario, then hand the deep dive to the concern skill that owns it.
- If the user names a CRAFT TERM, route straight to the concern skill (table above) — do not
  re-explain here.
- If the user wants step-by-step guidance, run `coach`: ask ONE question, wait, apply Pat's tool,
  surface the next choice point. Never list-and-leave; never monologue 14 steps.
- If the user gives a draft, that is diagnosis — route to `/songwriting:diagnosis` (`demo` for any
  stage, `diagnose` for near-complete).
- If the user pastes an incomplete fragment / idea / half-song, route to `fragment` or `idea` here.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## What this plugin does not do

Pat's books cover lyric craft and structure. This plugin does not handle melody writing, chords,
arrangement, production/mixing, vocal coaching, or music business. For Suno prompt formatting use
`/songwriting:suno` — a separate capability that formats a finished lyric; it does not load these
skills, and these skills do not import from it.
