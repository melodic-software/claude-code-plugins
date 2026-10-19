---
description: "Review, audit and rewrite a lyric with Pat Pattison's methods: demo review at any stage, full-draft diagnosis, the pre-lock audit checklist, labeled variations across six axes and critique-driven rewrite. Use when: 'what's wrong with my song', 'review my draft', 'is this any good', 'review this demo', 'audit this line before I lock it', 'give me 5 versions of line 3', 'rewrite this using Pat's checklist'. For blank-page starts use /songwriting:workflow."
argument-hint: "[diagnose|demo|audit|variations|rewrite] [args]"
user-invocable: true
disable-model-invocation: false
---

**Arguments.** `[diagnose|demo|audit|variations|rewrite] [args]`. e.g., /songwriting:diagnose,
/songwriting:diagnose audit "...", /songwriting:diagnose variations "...". Full actions in body.

## Mandatory pre-flight. Response Filter

Before emitting a critique, diagnosis, audit verdict, variation set, or rewrite, run **§3 Critique
filter** and **§8 Pre-lock filter** of
[response-filter](../../context/pat-pattison/research/response-filter.md) (add **§2
Line-writing** when producing rewritten lines). NAME each box's pass / fail / skip-with-reason
(aloud or in reasoning); correct before emission. Skips are valid; silent skips are not.
List-and-leave critique is the default this filter catches.

`variations` and `rewrite` EMIT lines. §2's **Reference:** line is a load list, not a
bibliography: §2 has not run until the files it names were read this session, at minimum
[meter](../../context/pat-pattison/research/meter.md) and
[phrasing](../../context/pat-pattison/research/phrasing.md) before the first candidate, plus
[metaphor](../../context/pat-pattison/research/metaphor.md) when the fix calls for an image or a
figure, per [response-filter](../../context/pat-pattison/research/response-filter.md) "§2
Line-writing filter". The Action Router's `Load` column is a routing hint; this is a precondition
of emission. A candidate table written before those files were opened ran on model priors, the
failure §2 exists to catch, and naming the §2 boxes does not undo it. Then cycle §2's boxes inside
[line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md), the full cycle per
candidate before it is shown. Auditing a line the writer already HAS is the other direction: that
stays [audit-checklist](../../context/pat-pattison/research/audit-checklist.md) (pre-lock). Line
emission is `/songwriting:co-write`'s, and its input gate travels with the lines: same gate,
checked here. *(Plugin-authored, not Pat Pattison's.)*

Diagnosis names problems; it does not silently rewrite the whole song.

Method content is Pat Pattison's, under the plugin-root `../../context/pat-pattison/`; a future
author's method plugs in at `context/<author>/` without changing this skill, the author seam per
the plugin-root `../../README.md` "Method content and the author seam".

## Action Router

`/songwriting:diagnose <action> [args]`. Parse `$ARGUMENTS`: first token = action when it matches
a listed action, remainder = args; otherwise treat all of `$ARGUMENTS` as payload for the default.
No action → route on completion stage (partway draft → `demo`; near-complete → `diagnose`).

| Action | Use when the user asks for | Load |
| --- | --- | --- |
| `diagnose` (default) | "what's wrong with my song", "review my draft" (near-complete) | [five-compositional-elements](../../context/pat-pattison/research/five-compositional-elements.md), [stable-unstable-meta](../../context/pat-pattison/research/stable-unstable-meta.md), [prosody](../../context/pat-pattison/research/prosody.md) |
| `demo` | "review this demo", "where do I take this", "lyric is partway done" | [demo-review](../../context/pat-pattison/research/demo-review.md), [templates/demo-review-prompt](../../context/pat-pattison/templates/demo-review-prompt.md) |
| `audit` | "line-by-line review", "pre-lock checklist", "should this lock" | [audit-checklist](../../context/pat-pattison/research/audit-checklist.md), [templates/audit-checklist-prompt](../../context/pat-pattison/templates/audit-checklist-prompt.md), [templates/diagnose-section-prompt](../../context/pat-pattison/templates/diagnose-section-prompt.md) |
| `variations` | "give me 5 versions of this line", "different POV / image / vowel", "alternate this" | [variations](../../context/pat-pattison/research/variations.md), [templates/variations-prompt](../../context/pat-pattison/templates/variations-prompt.md), [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md), [meter](../../context/pat-pattison/research/meter.md), [phrasing](../../context/pat-pattison/research/phrasing.md) |
| `rewrite` | a lyric critique or rewrite using Pat's checklist | [stable-unstable-meta](../../context/pat-pattison/research/stable-unstable-meta.md), [five-compositional-elements](../../context/pat-pattison/research/five-compositional-elements.md), [prosody](../../context/pat-pattison/research/prosody.md), [meter](../../context/pat-pattison/research/meter.md), [phrasing](../../context/pat-pattison/research/phrasing.md), [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md), [object-writing](../../context/pat-pattison/research/object-writing.md), [rhyme-strategy](../../context/pat-pattison/research/rhyme-strategy.md), [cliche](../../context/pat-pattison/research/cliche.md) |

## Handlers

- Name the dominant problem; offer one focused revision. Do not list every issue.
- Audit boxes are tools, not gates: present each as a deliberate choice point, pass/fail/skip. A
  writer may skip any box, but a skip names a reason; silent skips are not OK.
- The rubric's passes are **not** skippable: they are the writer's standing rule for every
  candidate, not choice points offered to him. Run the countable passes as commands, per the rubric
  row of `/songwriting:co-write`'s hard gate (syllables from `datamuse.sh syllables`, repeats from a
  word-frequency count), and let that gate's skeptic row test the judgment passes from a fresh
  context. Rewrites and variation sets are line emission: cycle
  [line-edit-rubric](../../context/pat-pattison/research/line-edit-rubric.md) in full on every
  candidate, pass 1 clean, and DROP any candidate a pass flagged rather than presenting it flagged.
  Two rejected executions in one slot ends generation for that slot: hand the concept back per
  `/songwriting:co-write` Handlers.
- `variations` output reaches the writer as full section blocks IN CONTEXT: changed lines marked
  `►`, one labeled block per variation, 3-4 per chat menu; scansion maps and per-candidate craft
  notes go to the `variations/` file. Never a bare one-line candidate in a table. See
  [variations](../../context/pat-pattison/research/variations.md) "Presenting the candidates. Chat
  vs file".
- `variations` and `audit` judge candidates against the WRITER's register, not genre and not
  taste. Load [voiceprint](../../context/pat-pattison/research/voiceprint.md); if none exists, name
  that as a skipped gate instead of ruling on register anyway.
- An incomplete fragment, idea or half-song is the wrong skill: invoke `/songwriting:workflow`
  (`fragment` / `idea`) via the Skill tool.

## Persistence and template overrides

Write generated files to the paths in
[artifact-persistence](../../context/pat-pattison/research/artifact-persistence.md) "Where
generated work persists", and honor a consuming project's own songwriting layout when it defines
one. Before loading any bundled `templates/<name>.md`, check
`${CLAUDE_PROJECT_DIR}/songwriting/templates/pat-pattison/<name>.md` first: a project-level
override wins over the bundled default, first match, per that file's "Template override".

## Related skills

- Blank page, seed, or stuck fragment → `/songwriting:workflow`
- The craft dimensions a diagnosis names → `/songwriting:rhyme`, `/songwriting:meter-prosody`,
  `/songwriting:song-form`, `/songwriting:object-writing`
