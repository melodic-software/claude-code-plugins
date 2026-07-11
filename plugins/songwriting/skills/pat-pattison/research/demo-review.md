# Demo Review — Diagnose at Any Stage

The writer has a lyric in progress at any completion stage — one verse, a
chorus + bridge, a near-finished draft, even just a chorus stanza — and
wants direction: "what's missing?", "where do I take this?", "what's the
next move?"

Distinct from:

- `brainstorm.md` — nothing yet
- `idea-to-title.md` — seed only
- `fragment-development.md` — single fragment
- `/pat-pattison diagnose` — assumes a complete-ish draft; this assumes ANY stage
- `/pat-pattison rewrite` — execute a rewrite (this file precedes that)

## When to load

Trigger phrases: "review this demo", "where do I take this", "what's
missing here", "this lyric is partway done", "I have this much — what now",
"what's the next pass", "is this any good as a starting point", "demo
review", "stage review".

## Step 1 — Stage detection

What do you actually have?

| Stage | What's present | What's needed |
|---|---|---|
| **Title only** | Title decided, nothing else | Route to `idea-to-title.md` continuation: object-write the world, draft central section |
| **Chorus only** | Chorus stanza drafted | Need: verses that prepare it; check chorus repaintability |
| **One verse only** | Single verse, no chorus | Need: central section decision (refrain in this verse? separate chorus?); world-building for verse 2 |
| **Verse + chorus** | One V + Ch | Need: verse 2 (box-model second box); bridge decision; ending |
| **Full draft, first pass** | All sections present, polish needed | Run full diagnose pass; surface dominant problem |
| **Near-final** | Polishing | Pre-lock audit-checklist; one-focused-revision pass |
| **Scratch lyric for melody** | Lyric written to fit existing music | Greedy-spot scan; lyric-melodic alignment (per `lyric-melodic-roadmaps.md`) |
| **Lyric reverse-engineered from style brief** | AI-generated or co-writer-supplied; needs craft inspection | Full diagnose + likely cliche / abstract scan |

## Step 2 — Read aloud once, no analysis

Per Pat's discipline. First pass is for sensation, not analysis. Mark
where:

- The ear hesitates (stress trip)
- The ear coasts (forgettable line)
- The ear is grabbed (strong moment)
- The ear is confused (POV / image / logic)

Don't diagnose yet. Just mark.

## Step 3 — Stage-appropriate diagnosis

Different stages need different passes. Don't run all 12 audits on a
chorus-only stub.

### If chorus-only

- Is the title in a hot spot (first line, last line, last line of a stanza)?
- Is the chorus repaintable? Could the same words mean different things in
  V1 → V2 → V3 contexts?
- Is the chorus tense-neutral / POV-neutral (per `repetition.md`)?
- Does the rhyme scheme close (strong rhyme types, balanced phrases) or
  push forward (unstable rhyme, deceptive closure)? Does that match the
  chorus's emotional job?

### If verse-only

- Is the central idea implied or named in the verse?
- Is there a refrain candidate (a line that could close every verse)?
- Are power positions doing work (line 1 strong, last line strong)?
- Sensory specificity: are there Rusty's-collar images? Or is the verse
  abstract telling?
- Whose verse is this — what POV? Is it consistent?

### If V+Ch

- Does V → Ch hand off? Is there a trigger line setting up the chorus?
- Does the chorus take a different emotional altitude from the verse, or
  the same one?
- Form decision: are you in V/Ch territory (chorus repeats) or V/Refrain
  (the title closes each verse)?

### If full draft, first pass

Run the diagnose pass (per `workflows.md` Scenario 2):

1. Five Compositional Elements scan per section
2. Stable/unstable scan
3. Cliche scan
4. Abstraction scan (Rusty's-collar test on every telling line)
5. Second-verse repair (travelogue test)
6. Repetition check (repaintable chorus)
7. POV consistency
8. Hot-spot audit (line 1 + last line of each section)
9. Hook check (title position, hook rhythm setup)
10. Sing aloud — last pass

Identify the **dominant problem**. Stop there. Do not list 10 problems —
the writer cannot fix 10 problems in one revision pass.

### If near-final / polish

Pre-lock audit (per `audit-checklist.md`):

- Per-line checklist on every line
- Per-section checklist on each section
- Pre-lock-title checklist if title is still moving
- Pre-lock-form checklist if structure is still moving

The polish pass surfaces the LAST move before lock — usually one of:

- A single line that drags
- A rhyme stability mismatch
- A POV bobble
- A weak power-position
- A greedy spot

### If scratch lyric for melody

Lyric-melodic alignment pass (per `lyric-melodic-roadmaps.md`):

- Map melodic phrases (where they breathe)
- Greedy-spot scan (stress mismatches)
- Stable/unstable per section
- Three alignment fixes (change melody, change lyric, repeat-a-word bridge)

## Step 4 — Surface ONE focused next move

Pat's coach posture: name the dominant problem, propose one focused fix,
return ONE finding. Not a punch list.

Format:

```
Stage detected: [one of above]

Strongest material:
- [specific element that's working — image, line, rhythm, prosodic move]

Dominant next move:
- [one specific revision direction, not a list]

Rationale:
- [why this move addresses the highest-leverage problem]

If/when this lands, the next pass would be:
- [secondary move, deferred until dominant is resolved]
```

Surface secondary problems briefly (one line each) but do NOT propose
fixes for them yet. The writer can revisit them after the dominant fix
lands.

## Step 5 — Hand off to action

Depending on the dominant move, route to:

| Dominant move | Next action |
|---|---|
| Verse 2 weak / travelogue | `verse` + `box-model.md` |
| Chorus doesn't repaint | `repetition.md` chorus-stripping workflow |
| Title in wrong position | `hook.md` strategies + form change |
| Greedy spots / stress problems | `align-melody` + `meter.md` |
| Cliche-saturated | `cliche` + `metaphor` (recipe) |
| Form fights the emotion | `form.md` + `song-forms.md` |
| Abstract telling without images | `object-writing.md` Rusty's-collar pattern |
| Bridge missing / restating | `bridge.md` |
| Rhyme weak | `rhyme-generation.md` discipline |
| Polish line by line | `audit-checklist.md` |

## What this file does NOT do

- Does not rewrite. This is diagnosis. Rewriting is `rewrite` action.
- Does not list 10 problems. One dominant, surface secondaries briefly.
- Does not assume a complete draft. Stage detection is Step 1.
- Does not skip the read-aloud. Step 2 is non-negotiable.

## Artifact pattern

Demo review notes land in `songwriting/songs/<slug>/research/demo-review-<TS>.md`
or in the conversation if no slug yet. The dominant-move + secondary list
becomes the input for the next session's revision.

## Cross-references

- `workflows.md` — Scenario 2 (existing song revision), Scenario 6 (diagnose without rewrite)
- `five-compositional-elements.md` — Pentad diagnostic per section
- `stable-unstable-meta.md` — section-level prosody scan
- `cliche.md` — cliche taxonomy
- `verse-development.md` — travelogue test, power positions
- `repetition.md` — repaintable chorus
- `point-of-view.md` — POV consistency
- `hook.md` — title position, hook rhythm
- `lyric-melodic-roadmaps.md` — scratch-to-melody case
- `audit-checklist.md` — pre-lock polish
