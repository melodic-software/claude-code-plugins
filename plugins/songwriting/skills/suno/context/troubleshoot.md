# Troubleshooting lane

Most Suno issues are **prompt-side preventable**. The model can't fix audio post-generation; the fix is "rewrite the prompt and regenerate." Maps symptoms to root causes and prompt-side fixes.

## Master pitfalls table

| Pitfall | Symptom | Root cause | Fix |
|---------|---------|------------|-----|
| Vague genre (`pop`, `rock`) | Generic AI sound, no character | Model defaults to genre average | Specify subgenre + era + tonal cue (`synth-pop, 80s-inspired`) |
| 5+ stacked genres | Muddy mix, incoherent style | Conflicting feature signals | Pick 1-2 max, or use a clear hybrid (`nu-metal dubstep`) |
| 9+ mood words | Conflicting emotional signals | Model can't reconcile contradictions | 2-3 related moods (`nostalgic, hopeful` not `happy sad triumphant melancholic dreamy`) |
| `amazing`, `epic`, `beautiful` | Zero effect on output | Value judgments aren't acoustic descriptors | Replace with `raspy`, `breathy`, `intimate`, `belted` |
| BPM as descriptor (`fast`) | ±20 BPM drift from intent | Descriptor → wide range | Use numeric (`128 BPM`) — ~90% adherence in v5.5 |
| Long sentences with internal rhymes | Hallucinated / garbled lyrics | Model confused by complex structure | Break into shorter lines, simpler rhyme scheme |
| `(x2)` after a lyric line | Repeat is ignored | Notation not parsed | Write the line twice with minor variation |
| ALL-CAPS every word | Effect dilutes to no effect | Loses contrast | Cap only turning-point words |
| `no drums` in drum-heavy genre alone | Drums still appear | Negative without positive | Pair with positive (`piano only, no drums`) |
| 5+ exclusions stacked | Conflicting signals, exclusions ignored | Model picks and chooses | Cap at 2-3 negatives |
| Style prompt > 1000 chars | Trailing tags ignored | Silent truncation | Front-load critical content |
| Lyrics > 60 lines | Rushed delivery, sections skipped | Time budget exceeded | Trim to 30-40 lines for 3-4min song |
| Naming artists directly (`like Drake`) | Likely blocked or ignored | Filter | Use sound descriptors (`Toronto trap bounce`, `silk-smooth R&B falsetto`) |
| Vocal descriptor + active Voice/Custom Model | Conflict, weird vocal artifacts | Cloned identity vs prompted identity | **Drop gender/tone descriptors** from style when Voice/Custom Model active |
| Same prompt regenerated 3+ times | Diminishing returns, repetitive output | Cached patterns | Rotate synonyms (`gritty → raw → visceral → unpolished`) |
| Single generation, settle on it | Missed better takes | Variance is the friend | **Always generate 4+ versions, A/B compare** |

## Symptom-specific diagnoses

### "Vocals are appearing on my instrumental"

**Why:** Pop and Gospel are most vocal-prone genres. If lyrics field is empty or absent, Suno may invent vocals.

**Fix:**

1. Add `[Melodic Instrumental]` as the only "lyrics" content
2. Include `instrumental` in the style prompt
3. Add `no vocals` at end of style prompt
4. In Custom mode, ensure the Lyrics field has `[Melodic Instrumental]` tag explicitly

### "Lyrics are garbled / don't match what I wrote"

**Why:** Complex rhyme schemes, run-on sentences, missing punctuation, or lyrics exceeding ~3,000 chars — the quality threshold past which Suno rushes, skips, or garbles (hard cap is 5,000 on v4.5/v5/v5.5; verified 2026-07-18, third-party testers — no official limit published).

**Fix:**

1. Trim to ≤30-40 lines for a 3-4 min song
2. Add periods/commas where natural breath happens
3. Break long sentences across lines
4. Simplify rhyme scheme — internal multi-syllable rhymes confuse the model
5. Verify total char count — paste into a counter; if > 3,000 chars, trim (quality threshold; the 5,000 hard cap is not the problem)

### "BPM is off by 20+"

**Why:** Used a descriptor (`fast`, `medium-tempo`) instead of numeric.

**Fix:**

1. Replace descriptor with `<NUMBER> BPM` (e.g., `128 BPM`)
2. Place after instrumentation, before production
3. Reinforce with groove tag if needed (`128 BPM, four-on-the-floor`)

### "Genre bleed — asked for jazz, got jazz-fusion-rock"

**Why:** Stacked too many genres, OR mood words contradict the genre, OR instrumentation doesn't match.

**Fix:**

1. Cap genre tags at 1-2
2. Match mood + instrumentation to genre conventions (acoustic guitar + brushed drums + 88 BPM = NOT jazz fusion; that's folk)
3. Add explicit negatives for the bleed-target (`no rock guitar`, `no fusion synths`)

### "Vocals sound bleedy / phasey on duets"

**Why:** Suno's known duet artifact — vocal lines bleeding between lead and backing.

**Fix:**

1. Use `[Duet]` tag explicitly in lyrics
2. Use `[Male Vocal]` and `[Female Vocal]` tags to mark each part's lines
3. Avoid `[Stacked Harmonies]` if you want clean separation
4. Replace Section (Pro/Premier) on the worst-affected section with explicit single-vocal direction
5. Generate 4+ versions — variance is high on duets

### "Exclusions are being ignored"

**Why:** Negatives placed mid-prompt, OR conflicting positive elsewhere, OR too many negatives stacked.

**Fix:**

1. Move ALL negatives to **end** of the style prompt
2. Pair each negative with a positive (`piano only, no guitar` instead of `no guitar`)
3. Cap at 2-3 negatives total
4. Use the **Exclude field** in Custom mode Advanced Options as alternative
5. Increase specificity (`no electric guitar` not `no guitar`)

### "My voice clone sounds wrong"

**Why:** Style prompt has gender/tone descriptors that conflict with the cloned identity.

**Fix:**

1. **Drop ALL vocal direction descriptors** from the style prompt
2. Raise Audio Influence slider higher (≥70%)
3. Re-record cleaner acapella source if voice quality is the issue (3 clips, emotional range, quiet room)

### "Output is repetitive / boring after 5 regenerations"

**Why:** Diminishing returns from cached patterns on identical prompts.

**Fix:**

1. **Rotate synonyms** — change the wording while preserving intent: `gritty → raw → visceral → unpolished → analog-warm`
2. Bump Weirdness slider up 10-20%
3. Change one variable at a time — measure what improves
4. Try a different mood word pair

### "Title doesn't appear in the song"

Expected — the title is a metadata label only and has no effect on musical output. If you want a phrase sung, put it in the lyrics (typically as the chorus hook).

### "Section tags are being sung literally"

**Why:** Section tag placed mid-line instead of on its own line.

**Fix:**

1. Always put `[Verse]`, `[Chorus]`, etc. on their **own line**
2. Inline cues use `(parentheses)` not square brackets: `In the shadows (whispered)` not `In the shadows [whispered]`

## Regeneration strategy

When the first 4 generations all miss, don't keep re-rolling the same prompt:

1. **Identify the failure mode** (use the table above)
2. **Change one variable** — the most likely culprit per the diagnosis
3. **Generate 4 more** with the changed variable
4. **A/B compare** — if better, lock that change and iterate on the next variable
5. **If no improvement after 3 variable changes**, the genre/mood/instrumentation triangle may be inconsistent — rebuild the prompt from scratch using the 6-layer formula
