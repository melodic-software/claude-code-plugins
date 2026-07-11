# Variations — Labeled Alternates

When the writer asks for "5 versions of this line" / "another way to say
this" / "what else could verse 2 be" — generate variations along a chosen
axis with explicit labels so the writer compares deliberately.

Pat's stance: more options = better choices. Variations are not waste; they
are the writer choosing rather than settling.

## When to load

Trigger phrases: "give me 5 versions", "alternate POV", "different way to
say this", "what else could this be", "rewrite this line three ways",
"variations", "alternatives", "options for this line", "label these
differently".

## Axes for variation

Six primary axes. Pick the axis that matters for the choice the writer is
making, not all axes at once.

### Axis 1 — POV shift

Same line / section, different speaker or address.

- 1st person (I) ↔ 2nd person (you) ↔ 3rd person (he/she/they)
- Direct address (talking to "you") ↔ Narrative (telling about "you")
- Inclusive 1st person plural (we) — late shift can land hard

Per `point-of-view.md` camera distances. POV shifts change emotional
distance dramatically.

### Axis 2 — Image shift

Same idea, different concrete image carrying it.

- The same telling line preceded by a different Rusty's collar
- Storm-anger swapped for clock-anger (one cliche family for another less
  used)
- Indoor image swapped for outdoor; weather swapped for body; etc.

Per `object-writing.md` Rusty's-collar rewrite pattern + `metaphor.md`
metaphor recipes.

### Axis 3 — Vowel shift

Same line meaning, different stressed vowel (changes singability + rhyme
neighborhood entirely).

- "I'm waiting at the window" → "I'm hiding in the corner" (long-A → long-I)
- Useful when the line's current vowel rhymes only with cliche partners
- Useful when the line's current vowel clashes with the melody's pitch
  contour

Each variation lists the new stressed vowel.

### Axis 4 — Stress count shift (length)

Same line, different stress count.

- Tetrameter (4-stress) → pentameter (5-stress) for slowdown
- Tetrameter → trimeter (3-stress) for acceleration / common-meter close
- Per `meter.md` paradigms and Pat's Structural Pentad

Useful for fixing greedy spots, matching melody, restructuring rhyme
scheme.

### Axis 5 — Rhyme-type shift

Same content, different rhyme stability tier in the rhyme position.

- Perfect rhyme → family rhyme → assonance → consonance → no rhyme
- Each tier changes the section's emotional closure
- Use to shift section from stable (closure) to unstable (forward motion)

Per `rhyme-strategy.md` decision matrix.

### Axis 6 — Tone-of-voice shift

Same content, different emotional register.

- Controlled ↔ raw
- Ironic ↔ sincere
- Resigned ↔ accusatory
- Whispered ↔ declared

Per `prosody.md` tone-of-voice stability. Changes diction, syntax,
imagery.

## Step 1 — Pick the axis

Ask which dimension the writer is uncertain about. If the writer doesn't
know, surface 2-3 axis options and let them pick:

- "Are you uncertain about who's speaking? → POV axis"
- "Is the image landing? → image axis"
- "Does the line sing? → vowel or stress count axis"
- "Is the rhyme too closed / open? → rhyme-type axis"
- "Is the tone right? → tone-of-voice axis"

If multiple axes apply, run them as separate batches — one axis per batch
keeps comparison deliberate.

## Step 2 — Generate 4-6 labeled variations

Each variation gets an explicit label naming what changed and why.

Format:

```
ORIGINAL: <the line as written>
  vowel: <stressed vowel>
  stress: <count>
  POV: <1st/2nd/3rd>
  rhyme position: <perfect/family/assonance/etc>
  notes: <any other relevant>

VARIATION 1 — [axis: POV shift, 1st → 2nd]
  <new line>
  vowel: <same / shifted to X>
  stress: <count>
  POV: 2nd
  rhyme position: <impact>
  effect: <one-line emotional / structural effect>

VARIATION 2 — [axis: image shift, weather → body]
  <new line>
  ...

VARIATION 3 — [axis: vowel shift, long-A → long-O]
  <new line>
  ...

VARIATION 4 — [axis: stress count shift, 4-stress → 3-stress]
  <new line>
  ...

VARIATION 5 — [axis: rhyme-type shift, perfect → family]
  <new line>
  ...

VARIATION 6 — [axis: tone-of-voice shift, controlled → raw]
  <new line>
  ...
```

If the writer chose ONE axis in Step 1, do not span 6 axes. Generate 4-6
variations within that axis.

## Step 3 — Highlight the trade-offs

For each variation, name what the variation gains AND what it loses
compared to the original.

- "Variation 1 gains intimacy (2nd person); loses universality (1st
  person's anyone-can-say-it quality)."
- "Variation 3 gains family-rhyme options; loses long-A vowel's openness
  in the chorus."

The writer chooses by trade-off, not by what reads best in isolation.

## Step 4 — Do NOT pick a winner

Surface the labeled list with trade-offs. Let the writer choose.

If the writer asks which is best, push back gently: "the choice depends on
[the song's central emotion / the melody's pitch contour / the verse's POV
discipline]. Which matters most for this song?"

## Artifact pattern

Variations land in `songwriting/songs/<slug>/variations/<section>-<line>.md`
per the SKILL.md "Artifact Persistence" layout. Each variations file is a
labeled menu — not a
diff — so the writer can choose later.

Example file structure:

```
# Chorus L3 — variations

ORIGINAL (locked Wed): "..."

[Axis: image shift, weather → body]
- V1: ...
- V2: ...

[Axis: rhyme-type shift, perfect → family]
- V3: ...
- V4: ...

DECISION: V2, locked Thu. Reason: matches V1 verse's body-language palette.
```

The decision line locks the variation; archive the other options in the
same file rather than deleting them. They may help later songs.

## Common failure modes

| Failure | Recovery |
|---|---|
| Writer wants "best" instead of options | hold the line — Pat's framing: options first, choice second |
| Variations all on the same axis | re-distribute across 2-3 axes if scope is open |
| Variations diverge too far from original | reduce variation distance; small moves first |
| Variations break the section's prosody | drop the variation; surface the prosody constraint as the deciding factor |
| Writer can't decide | run `audit-checklist.md` per-line on each variation; let the audit surface the load-bearing trade-off |

## Cross-references

- `point-of-view.md` — POV axis source
- `object-writing.md` — image axis source
- `metaphor.md` — image-shift via metaphor recipes
- `meter.md` — stress-count axis source
- `rhyme-strategy.md` — rhyme-type axis source
- `prosody.md` — tone-of-voice axis source
- `audit-checklist.md` — per-line evaluation across variations
- `rhyme-generation.md` — vowel-shift rhyme implications
