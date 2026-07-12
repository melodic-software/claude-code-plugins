# Demo Review Prompt Template

Use when writer pastes a lyric at any completion stage and asks for
direction.

## Step 1 — Stage detection (model-side)

Examine the pasted lyric. Identify completion stage:

- Title only
- Chorus only
- One verse only
- Verse + chorus
- Full draft, first pass
- Near-final (polish stage)
- Scratch lyric for melody
- AI-generated / co-writer-supplied (needs craft inspection)

Confirm stage with writer if ambiguous.

## Step 2 — Read aloud (writer-facing)

```
Read the lyric aloud once. Don't analyze; don't fix. Mark:

- **Trip** — where the ear hesitates (stress trip / awkward phrasing)
- **Coast** — where the ear coasts (forgettable line)
- **Grab** — where the ear is grabbed (strong moment)
- **Confuse** — where the ear is confused (POV / image / logic)

Paste the marked-up lyric. We'll diagnose from where the ear told you the
truth, not from where you wanted truth to be.
```

## Step 3 — Stage-appropriate diagnose (model-side)

Different stages need different passes. Don't run all 12 audits on a
chorus-only stub.

### Chorus only

- Title in a hot spot? (first line / last line / last line of stanza)
- Repaintable? Could same words mean different things in V1 → V2 → V3
  contexts?
- Tense-neutral / POV-neutral (per `repetition.md`)?
- Rhyme scheme closes (strong rhyme types, balanced phrases) or pushes
  forward? Matches chorus's job?

### Verse only

- Central idea implied or named?
- Refrain candidate (line that could close every verse)?
- Power positions doing work (line 1 strong, last line strong)?
- Sensory specificity — Rusty's-collar images, or abstract telling?
- POV consistent?

### V + Ch

- Does V → Ch hand off? Trigger line setting up the chorus?
- Different emotional altitude V vs Ch, or same?
- V/Ch territory (chorus repeats) or V/Refrain (title closes each verse)?

### Full draft, first pass

Run sequenced diagnose:

1. Five Compositional Elements per section
2. Stable/unstable scan
3. Cliche scan
4. Abstraction scan (Rusty's-collar test on every telling line)
5. Second-verse repair (travelogue test)
6. Repetition check (repaintable chorus)
7. POV consistency
8. Hot-spot audit
9. Hook check
10. Read aloud — final pass

Identify the DOMINANT problem. Stop there.

### Near-final / polish

Pre-lock audit per `audit-checklist.md`:

- Per-line checklist on every line
- Per-section checklist
- Pre-lock-title / pre-lock-form checklists if those are still moving

### Scratch lyric for melody

Lyric-melodic alignment per `lyric-melodic-roadmaps.md`:

- Map melodic phrases
- Greedy-spot scan
- Stable/unstable per section
- Three alignment fixes

## Step 4 — Surface ONE focused next move (writer-facing)

```
**Stage:** <detected stage>

**Strongest material:**
- <specific element working — line, image, rhythm, prosodic move>

**Dominant next move:**
- <ONE specific revision direction, not a list>

**Why this move:**
- <addresses the highest-leverage problem>

**Secondary observations (deferred):**
- <one line each, no fix proposed>
- <...>

**If/when the dominant move lands, the next pass would be:**
- <secondary move, deferred until dominant is resolved>
```

## Step 5 — Hand off to action (model-side)

Route the dominant move to the right action:

| Dominant move | Route to |
|---|---|
| Verse 2 weak / travelogue | `verse` + `box-model.md` |
| Chorus doesn't repaint | `repetition.md` chorus-stripping |
| Title wrong position | `hook.md` + form change |
| Greedy spots / stress | `align-melody` + `meter.md` |
| Cliche-saturated | `cliche` + `metaphor-recipe` |
| Form fights emotion | `form.md` + `song-forms.md` |
| Abstract telling | `object-writing.md` Rusty's-collar |
| Bridge missing / restating | `bridge.md` |
| Rhyme weak | `rhyme-generation.md` |
| Polish line by line | `audit-checklist.md` |

## Coach posture

- Pat's rule: one focused finding. Not ten scattered notes.
- Surface secondaries briefly, do not fix them.
- Read aloud is non-negotiable (Step 2).
- If dominant problem is upstream (title doesn't fit form, form doesn't
  fit emotion), say so — fixing downstream lines won't help.

## Cross-references

- `demo-review.md` — full context
- `workflows.md` Scenarios 2, 6
- All diagnostic context files
