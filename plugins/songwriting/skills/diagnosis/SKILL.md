---
name: diagnosis
description: "Review, audit, and rewrite a lyric with Pat Pattison's methods — demo review at any completion stage, full-draft diagnosis against the five compositional elements and stable/unstable analysis, the pre-lock line/section audit checklist (tools, not gates), labeled variations across six axes, and critique-driven rewrite. Use when: 'what's wrong with my song', 'review my draft', 'is this any good', 'review this demo', 'audit this line before I lock it', 'give me 5 versions of line 3', 'rewrite this using Pat's checklist'. For blank-page starts use /songwriting:workflow."
argument-hint: "[action] [args] (e.g., /songwriting:diagnosis, /songwriting:diagnosis audit \"...\", /songwriting:diagnosis variations \"...\") — full actions in body"
user-invocable: true
disable-model-invocation: false
---

## Mandatory pre-flight — Response Filter

Before emitting a critique, diagnosis, audit verdict, variation set, or rewrite, run **§3 Critique
filter** and **§8 Pre-lock filter** of
[response-filter](../../context/pat-pattison/research/response-filter.md) (add **§2 Line-writing**
when producing rewritten lines). NAME each box's pass / fail / skip-with-reason; correct before
emission. Skips are valid; silent skips are not — list-and-leave critique is the default this
filter catches.

## Purpose

The review-and-revise layer: name the dominant problem, offer one focused revision, run the pre-lock
checklist as deliberate choice points, and generate labeled alternates. Diagnosis names problems;
it does not silently rewrite the whole song.

Method content is Pat Pattison's, under `context/pat-pattison/`. A future author's method plugs in
at `context/<author>/` without changing this skill.

## Action Router

`/songwriting:diagnosis <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → route on completion stage (partway draft → `demo`; near-complete → `diagnose`).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `diagnose` (default) | "what's wrong with my song", "review my draft" (near-complete) | [five-compositional-elements](../../context/pat-pattison/research/five-compositional-elements.md), [stable-unstable-meta](../../context/pat-pattison/research/stable-unstable-meta.md), [prosody](../../context/pat-pattison/research/prosody.md) |
| `demo` | "review this demo", "where do I take this", "lyric is partway done" | [demo-review](../../context/pat-pattison/research/demo-review.md), [templates/demo-review-prompt](../../context/pat-pattison/templates/demo-review-prompt.md) |
| `audit` | "line-by-line review", "pre-lock checklist", "should this lock" | [audit-checklist](../../context/pat-pattison/research/audit-checklist.md), [templates/audit-checklist-prompt](../../context/pat-pattison/templates/audit-checklist-prompt.md), [templates/diagnose-section-prompt](../../context/pat-pattison/templates/diagnose-section-prompt.md) |
| `variations` | "give me 5 versions of this line", "different POV / image / vowel", "alternate this" | [variations](../../context/pat-pattison/research/variations.md), [templates/variations-prompt](../../context/pat-pattison/templates/variations-prompt.md) |
| `rewrite` | a lyric critique or rewrite using Pat's checklist | [stable-unstable-meta](../../context/pat-pattison/research/stable-unstable-meta.md), [five-compositional-elements](../../context/pat-pattison/research/five-compositional-elements.md), [prosody](../../context/pat-pattison/research/prosody.md), [object-writing](../../context/pat-pattison/research/object-writing.md), [rhyme-strategy](../../context/pat-pattison/research/rhyme-strategy.md), [cliche](../../context/pat-pattison/research/cliche.md) |

## Handlers

- **Pre-flight ALWAYS:** run response-filter §3 + §8 (+ §2 when rewriting) before output.
- Name the dominant problem; offer one focused revision. Do not list every issue.
- Audit boxes are tools, not gates: present each as a deliberate choice point, pass/fail/skip — a
  writer may skip any box, but a skip names a reason; silent skips are not OK.
- If the user pastes an incomplete fragment/idea/half-song, this is the wrong skill — route to
  `/songwriting:workflow` (`fragment` / `idea`), not `diagnose`.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md), and honor a
consuming project's own songwriting layout when it defines one. Before loading any bundled
`templates/<name>.md`, check `${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md`
first — a project-level override wins over the bundled default.

## Related skills

- Blank page, seed, or stuck fragment → `/songwriting:workflow`
- The craft dimensions a diagnosis names → `/songwriting:rhyme`, `/songwriting:meter-prosody`,
  `/songwriting:song-form`, `/songwriting:object-writing`
