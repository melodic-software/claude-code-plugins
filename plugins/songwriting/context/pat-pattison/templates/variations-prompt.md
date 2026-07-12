# Variations Prompt Template

Use when writer asks for multiple versions of a line, section, or angle.
Generate labeled alternates so the writer chooses by trade-off, not by
gut.

## Step 1 — Confirm scope + axis (writer-facing)

```
What are you varying?
- [a] A single line
- [b] A section
- [c] An entire angle (POV / time / setting of the whole song)

And which axis matters here?
- **POV** — same content, different speaker / address
- **Image** — same idea, different concrete image
- **Vowel** — same meaning, different stressed vowel (changes rhyme territory)
- **Stress count** — same line, different length (4 → 5 → 3 stresses)
- **Rhyme-type** — same content, different stability tier
- **Tone-of-voice** — same content, different emotional register
- **Or** — say "all" if you want one variation per axis (broader sweep)

Paste what you're varying.
```

## Step 2 — Generate 4-6 labeled variations (model-side)

Format for output to writer:

```
**ORIGINAL:** <the line / section>
  vowel: <stressed vowel>
  stress: <count>
  POV: <1st / 2nd / 3rd>
  rhyme position: <perfect / family / assonance / etc>
  tone: <controlled / raw / etc>

**VARIATION 1** — [axis: <axis>, shift: <from> → <to>]
  <new content>
  vowel: <same or shifted>
  stress: <count>
  POV: <same or shifted>
  rhyme position: <impact>
  effect: <one-line emotional / structural>
  gains: <what improves>
  loses: <what gets sacrificed>

**VARIATION 2** — [axis: <axis>, shift: <from> → <to>]
  ...

**VARIATION 3** ...
**VARIATION 4** ...
[**VARIATION 5** — if useful]
[**VARIATION 6** — if useful]
```

If the writer chose ONE axis in Step 1, all variations share that axis
(internal variety within the axis). If they chose "all", spread across
2-4 axes.

## Step 3 — Highlight trade-offs (model-side)

Each variation gets a `gains` and `loses` line — what improves and what
gets sacrificed. The writer chooses by trade-off:

- "V1 gains intimacy (2nd person); loses universality."
- "V3 gains family-rhyme options; loses the long-A vowel's openness."
- "V5 gains forward motion (consonance); loses chorus-landing weight."

## Step 4 — Do NOT pick the winner (model-side)

If the writer asks which is best, push back:

```
The choice depends on:
- the song's central emotion
- the surrounding section's prosodic shape
- the melody's pitch contour (if known)
- the rhyme scheme commitments already made

Which constraint is load-bearing for this song?
```

Let the writer name the load-bearing constraint, then surface the
variation that best matches it.

## Step 5 — Lock + archive

After the writer picks:

- The chosen variation goes into `LYRIC.md`
- The other variations stay in `songwriting/songs/<slug>/variations/<section>-<line>.md`
  as an archived menu with a DECISION line naming the chosen variation and
  the reason

Archive format (per `variations.md`):

```
# Chorus L3 — variations

ORIGINAL (locked Wed): "..."

[Axis: image shift]
- V1: ...
- V2: ...

[Axis: rhyme-type shift]
- V3: ...
- V4: ...

DECISION: V2, locked Thu. Reason: matches V1 verse's body-language palette.
```

## Coach posture

- Pat's framing: options first, choice second. The writer's job is to
  choose, not to be told.
- The model's job is to generate options labeled with their trade-offs,
  not to recommend a winner.
- If variations all collapse on one axis, broaden. If the writer can't
  decide, surface the load-bearing constraint and re-narrow.

## Common failure modes (recovery prompts)

```
Variations all look the same → axis too narrow; broaden by 1-2 dimensions

Variations diverge too far → reduce variation distance; small moves first

Variations break section prosody → drop the broken variation; surface the
prosody constraint as the deciding factor

Writer can't decide → run `audit-checklist.md` per-line on each variation;
let the audit surface the load-bearing trade-off
```

## Cross-references

- `variations.md` — full context, six axes definitions
- All axis-source context files (point-of-view, object-writing, metaphor,
  meter, rhyme-strategy, prosody)
- `audit-checklist.md` — Step 5 recovery
