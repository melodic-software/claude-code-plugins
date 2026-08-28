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
| Tag-only section as repeat shorthand (bare `[Chorus]`, no lyrics under it) | Adjacent section absorbed — its lyrics sang in the empty slot, and that section is missing | Observed once; adjacency is the correlate, mechanism not established | Write full lyrics under every repeated section — see "My bridge is missing / another section sang its lyrics" |
| ALL-CAPS every word | Effect dilutes to no effect | Loses contrast | Cap only turning-point words |
| `no drums` in drum-heavy genre alone | Drums still appear | Negative without positive | Pair with positive (`piano only, no drums`) |
| 5+ exclusions stacked | Conflicting signals, exclusions ignored | Model picks and chooses | Cap at 2-3 negatives |
| Style prompt > 1000 chars | Trailing tags may be weakly followed or ignored | Later content may receive less attention; silent truncation is unverified | Front-load critical content |
| Lyrics > 60 lines | Rushed delivery, sections skipped | Time budget exceeded | Trim to 30-40 lines for 3-4min song |
| Short-line stacks (clipped fragments) | Excess pauses between lines, choppy delivery | Suno phrases at every line break — separation is what the break buys | Join lines in the Suno lyrics field only, leaving the page lyric unchanged — see "There's too much pause between lines" |
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
3. Add `no vocals` to the style prompt
4. In Custom mode, ensure the Lyrics field has `[Melodic Instrumental]` tag explicitly

### "Lyrics are garbled / don't match what I wrote"

**Why:** Complex rhyme schemes, run-on sentences, missing punctuation, or lyrics exceeding ~3,000 chars — the quality threshold past which Suno rushes, skips, or garbles (hard cap is 5,000 on v4.5/v5/v5.5; verified 2026-07-18, third-party testers — no official limit published).

**Fix:**

1. Trim to ≤30-40 lines for a 3-4 min song
2. Add periods/commas where natural breath happens
3. Break long sentences across lines
4. Simplify rhyme scheme — internal multi-syllable rhymes confuse the model
5. Verify total char count — count the lyrics text rather than sending the writer to a counter; if > 3,000 chars, trim (quality threshold; the 5,000 hard cap is not the problem)

### "There's too much pause between lines / the delivery is choppy"

**Why:** Suno phrases at every line break — the same mechanism that makes "one idea per line" good default advice. Separation is what a break buys, so a stack of short clipped lines buys too much of it: the model sets a phrase boundary after each fragment and the section returns as a run of pauses rather than a sung line. The words are not the problem; the line endings are being read as phrasing instructions. This is the entry above turned too far — "break long sentences across lines" has an edge past which it backfires.

**Fix:**

1. Find the section with the shortest lines — a bridge or pre-chorus written as clipped fragments is the usual culprit
2. In the **Suno lyrics field only**, join the lines that should sing as one phrase onto one line
3. **Leave the page lyric alone** — the join is an input transformation for Suno, not an edit to the song. Keep two artifacts: the lyric as written, and the Suno-input form
4. Join no more than the phrasing needs, then regenerate and compare against the version without the joins — every join gives up a melodic boundary you may have wanted
5. Do not "fix" this by cutting words or shortening the section

**Evidence:** the line-break mechanism is established at MEDIUM and is not in question. The **failure edge** — that short-line stacks over-separate, and that joining at the prompt layer fixes it — is `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`: one five-line clipped bridge on v5.5, fixed on regeneration by joining lines in the Suno field while the page lyric kept its lineation. Where a first-hand observation sits relative to the confidence ladder: see [Confidence flags](../SKILL.md). Full mechanism statement: [lyrics.md](lyrics.md) "Line breaks cut both ways".

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

**Why:** Conflicting positive elsewhere, OR too many negatives stacked. Prompt position is not a verified cause.

**Fix:**

1. Pair each negative with a positive (`piano only, no guitar` instead of `no guitar`)
2. Cap at 2-3 negatives total
3. Use the **Exclude field** in Custom mode Advanced Options as alternative
4. Increase specificity (`no electric guitar` not `no guitar`)

Grouping all negatives at the end of the style prompt is a readability convention, not a verified adherence rule — do it for legibility, but do not expect it to fix an ignored exclusion on its own.

### "My voice clone sounds wrong"

**Why:** Style prompt has gender/tone descriptors that conflict with the cloned identity.

**Fix:**

1. **Drop ALL vocal direction descriptors** from the style prompt
2. Raise Audio Influence when resemblance is poor. Suno publishes no number; `>=70%` is only a community-derived, unverified starting point
3. Re-record cleaner acapella source if voice quality is the issue (one continuous 90-120s clip carrying the emotional range within it, same mic, quiet or treated room)

### "Output is repetitive / boring after 5 regenerations"

**Why:** Diminishing returns from cached patterns on identical prompts.

**Fix:**

1. **Rotate synonyms** — change the wording while preserving intent: `gritty → raw → visceral → unpolished → analog-warm`
2. Bump Weirdness slider up 10-20%
3. Change one variable at a time — measure what improves
4. Try a different mood word pair

### "Title doesn't appear in the song"

Expected — the title has minimal or no known effect on musical output; community reports differ. If you want a phrase sung, put it in the lyrics (typically as the chorus hook).

### "Section tags are being sung literally"

**Why:** Section tag placed mid-line instead of on its own line.

**Fix:**

1. Always put `[Verse]`, `[Chorus]`, etc. on their **own line**
2. Inline cues use `(parentheses)` not square brackets: `In the shadows (whispered)` not `In the shadows [whispered]`

### "My bridge is missing / another section sang its lyrics"

**Why:** An empty `[Chorus]` tag — the tag alone on its line with no lyrics under it, used as "repeat the chorus" shorthand — sat immediately above a `[Bridge]` that did carry lyrics. Suno sang the bridge's lyrics in the chorus slot and dropped the bridge entirely. Observed once, 2026-08-12, on Suno v5.5.

**Fix:**

1. Write **full lyrics under every repeated section** — paste the chorus text out again under each `[Chorus]` rather than leaving the tag bare. It costs only characters, and `lyrics.md` already recommends reusing the chorus verbatim so the hook sticks
2. Count that repeated text against the lyrics budget — writing three choruses out adds real lines, and the 30-40-line / ~3,000-char guidance still holds. Trim elsewhere rather than going back to bare tags
3. If you keep a bare tag anyway, treat the shape as unverified: generate 4+ versions and check the section order in every one. Variance is high, so one clean generation is not evidence the shape is safe

The observed correlate is a **tag-only section directly adjacent to a lyric-bearing section**. That adjacency is what was seen — a candidate cause, not a demonstrated mechanism. One run cannot show that tag-only repeats always fail, only that they can, which is why this is recorded as a failure mode rather than rated on the confidence ladder.

**Evidence:** `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`. Where a first-hand observation sits relative to the ladder: see [Confidence flags](../SKILL.md).

**Untested:** whether a tag-only section is safe as the *final* section before `[Outro]`/`[End]`, with no lyric-bearing section after it. Neither endorsed nor ruled out — check the output if you try it. Distinct from the `Lyrics > 60 lines` row above, which is a length failure; this was observed at normal length.

## Regeneration strategy

When the first 4 generations all miss, don't keep re-rolling the same prompt:

1. **Identify the failure mode** (use the table above)
2. **Change one variable** — the most likely culprit per the diagnosis
3. **Generate 4 more** with the changed variable
4. **A/B compare** — if better, lock that change and iterate on the next variable
5. **If no improvement after 3 variable changes**, the genre/mood/instrumentation triangle may be inconsistent — rebuild the prompt from scratch using the 6-layer formula
