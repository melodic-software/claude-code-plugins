# Lyrics lane — full reference

Suno reads lyrics as a **structured document**. Tags on their own line tell the model what's a verse vs chorus vs interlude; vocal/performance tags tell it HOW to sing. Tags placed mid-line are sung as literal lyrics — always put on their own line or in `(parentheses)` for inline cues.

**Custom mode required** for any tag syntax. Simple mode auto-generates lyrics and ignores tags.

## Section tags (structural)

Place each on its own line at the start of the section.

| Tag | Purpose |
|-----|---------|
| `[Intro]` | Opening; usually sparse or instrumental |
| `[Verse]`, `[Verse 1]`, `[Verse 2]`, `[Verse 3]` | Narrative storytelling sections; vary melody per numbered verse |
| `[Pre-Chorus]` | Builds energy before the chorus |
| `[Chorus]` | Peak energy, repeated hook, full instrumentation |
| `[Post-Chorus]` | Extends chorus momentum |
| `[Hook]` | Catchy short memorable phrase (alternative to or alongside Chorus) |
| `[Refrain]` | Repeated line |
| `[Bridge]` | Contrasting middle section, often a key change |
| `[Break]` | Stripped-down minimalist contrast |
| `[Breakdown]` | Reduced complexity, often before final chorus |
| `[Build]`, `[Build-Up]` | Rising tension before a drop |
| `[Drop]` | High-energy payoff (EDM/dance/trap) |
| `[Interlude]` | Short instrumental connector |
| `[Outro]` | Closing wind-down |
| `[End]` | Hard stop (vs gradual fade) |
| `[Fade Out]`, `[Fade In]` | Volume change at boundary |
| `[Instrumental]`, `[Instrumental Break]`, `[Melodic Instrumental]` | No-vocal sections |
| `[Guitar Solo]`, `[Piano Solo]`, `[Drum Solo]`, `[Bass Solo]`, `[Saxophone Solo]`, `[Synth Solo]` | Instrument-specific solos |
| `[Spoken Word]` | Recited rather than sung |

`[Fade Out]` is attested; **`[Fade In]` is not** — no source states it. It is kept because nothing places it outside the recognized set, but do not assume it carries the same backing as `[Fade Out]`.

## Vocal delivery tags

Place before sections, after section tags, or inline as `(parenthetical)` cues. For inline use, keep cues to 1-3 words — longer phrases get sung as lyrics.

| Category | Tags |
|----------|------|
| **Gender** | `[Male Vocal]`, `[Female Vocal]`, `[Male Vocalist]`, `[Female Vocalist]`, `[Androgynous Vocal]` |
| **Multiple voices** | `[Duet]`, `[Choir]`, `[Harmony]`, `[Harmonies]`, `[Backing Vocals]`, `[Stacked Harmonies]`, `[Call and Response]` |
| **Volume / intensity** | `[Whispered]`, `[Soft]`, `[Gentle]`, `[Quiet]`, `[Belted]`, `[Powerful]`, `[Shouted]`, `[Screamed]`, `[Growled]`, `[Intense]` |
| **Technique** | `[Falsetto]`, `[Head Voice]`, `[Chest Voice]`, `[Breathy]`, `[Raspy]`, `[Smooth]`, `[Soulful]`, `[Operatic]`, `[Nasal]`, `[Airy]`, `[Vocal Run]`, `[Melisma]`, `[Vibrato]`, `[Staccato]`, `[Legato]` |
| **Special** | `[Ad-lib]`, `[Ad-libs]`, `[Humming]`, `[Chant]`, `[Spoken Word]`, `[Whisper]` |
| **Rap-specific** | `[Rapped]`, `[Fast Rap]`, `[Slow Flow]`, `[Melodic Rap]`, `[Trap Flow]`, `[Boom Bap Flow]`, `[Mumble Rap]`, `[Double Time]` |

## Mood / effect tags

Inline or as section markers: `[Crescendo]`, `[Decrescendo]`, `[Swell]`, `[Silence]`, `[Reverb]`, `[Echo]`, `[Distortion]`.

## Per-section style overrides (the lyrics field as a SECOND style channel)

One of the most underused power techniques. The global style prompt sets the SONG's character; per-section overrides in lyrics control **dynamics, instrumentation, and production on a section-by-section basis** — solving the "every section sounds the same" problem.

### Syntax

Two separators work — both go on the same `[Tag]` line:

```
[Verse: whispered, acoustic guitar only]
[Bridge | dark | introspective | sparse]
[Chorus: belted, layered harmonies, full band]
```

- `[Tag: descriptor, descriptor]` — colon + comma list (most common in community examples)
- `[Tag | descriptor | descriptor]` — pipe-separated (also works)

Keep modifiers short — 2-4 words each, 2-5 modifiers per section.

### What you can override per section

<!-- ordinal note-value notation in table trips the spell-checker --><!-- spellchecker:off -->
| Axis | Examples |
|------|----------|
| **Instrumentation** | `piano only`, `no drums`, `full band`, `add strings`, `acoustic guitar only`, `add saxophone solo`, `808s and hi-hats only` |
| **Dynamics** | `quiet`, `building`, `explosive`, `stripped`, `intense`, `whispered`, `belted` |
| **Production** | `dry mix`, `heavy reverb`, `lo-fi`, `tape saturation`, `compressed`, `gated drums` |
| **Vocal** | `whispered`, `harmonized`, `double-tracked`, `gang vocals`, `solo voice`, `melismatic`, `staccato` |
| **Energy / mood** | `dark`, `triumphant`, `melancholic`, `aggressive`, `intimate`, `cinematic` |
| **Tempo feel** | `half-time feel`, `double-time`, `swing`, `straight 8ths` |
<!-- spellchecker:on -->

### Working example — full song with section overrides

```
[Intro: ambient pad, no rhythm]

[Verse 1: piano only, no drums, intimate]
First narrative beat — vocals carry it
Quiet, conversational, single-mic feel

[Pre-Chorus: drums enter, building tension]
Energy rising
Energy rising

[Chorus: full band kicks in, distorted guitar lead, gang vocals, big reverb]
THE HOOK
THE HOOK with backing layers

[Verse 2: piano + soft brushed drums, slightly fuller than verse 1]
Second narrative beat
Building from where we were

[Pre-Chorus: drums double, snare rolls]
Energy rising again
Higher this time

[Chorus: bigger than before, double-tracked vocals, layered harmonies]
THE HOOK
THE HOOK explosive

[Bridge: stripped to vocals + acoustic guitar, dry mix, no reverb]
Most vulnerable moment
Reveal

[Final Chorus: everything, key change up a step, choir backing]
THE HOOK
THE HOOK final blowout

[Outro: ambient pad returns, fade]
[Fade Out]
```

### Why this technique matters

- **Solves the dynamics problem** — without overrides, AI flattens into uniform density
- **Cheap to apply** — no extra char count cost, just better-organized lyrics
- **Composable with global style** — global = song character, per-section = movement within
- **More reliable than slider tweaks** — describe each section directly instead of hoping Style Influence interprets

### Descriptor density sweet spot — 4-7 elements per section

Empirical community consensus: **4-7 descriptors per `[Tag: ...]` block** produces the most reliable output.

- **Fewer than 4** → too much latitude, model fills space with defaults that may not match
- **4-7 elements** → sweet spot, model has clear direction without internal conflict
- **8+ elements** → "muddy results where descriptors compete," model picks subset randomly

### Recognized core section labels (HIGH reliability in v5.5 except `[Fade In]`)

Use these labels for structural section tags. Non-standard labels (`[Hook Variation]`, `[Final Push]`) get parsed as sung lyrics text, not structure. Instrument-specific solo labels are covered below.

```
[Intro] [Verse] [Verse 1] [Verse 2] [Verse 3]
[Pre-Chorus] [Chorus] [Hook] [Post-Chorus] [Refrain]
[Bridge] [Break] [Breakdown] [Build] [Build-Up]
[Drop] [Interlude] [Instrumental] [Instrumental Break]
[Outro] [End] [Fade Out] [Fade In]
```

`[Fade In]` is retained as unverified; no source states it.

For solos use `[Guitar Solo]`, `[Piano Solo]`, `[Drum Solo]`, `[Bass Solo]`, `[Saxophone Solo]`, `[Synth Solo]` — these are recognized. `[Synth Solo]` is community-attested (MEDIUM confidence); no source supports the claim that it is sung literally.

For anything else, **describe via parameterized syntax** instead of inventing a new label:

- Want a "synth solo": use `[Instrumental Break: synth solo, layered leads, 8 bars]` not `[Synth Solo Variation]`
- Want a "hook variation": use `[Chorus: stripped down, key change up a step]` not `[Hook Variation]`

### When per-section overrides get ignored

- **Section override contradicts global style** — global says `electronic dance`, override says `acoustic guitar only` → model picks one. Section overrides should be **specific instantiations** of global style, not wholesale contradictions
- **Too many overrides per section** — 8+ modifiers compete. Cap at 7 (sweet spot 4-7)
- **Override placed on wrong line** — must be on the `[Tag]` line itself, not on a lyric line below
- **Ambiguous descriptors** — `[Verse: better]` does nothing. Be specific: `[Verse: piano only, no drums]`
- **Lyric density mismatch** — `[Verse: piano only]` paired with 8 lines of dense lyrics gets ignored — model fills sonic space to support the vocal load. Either (a) shorter lyrics for sparse arrangements, or (b) more sonic descriptors to convince the model

### Brackets vs Parentheses — the v5.5 distinction

| Syntax | Purpose | Example |
|--------|---------|---------|
| `[Section]` | **Structural label** — boundary marker; read as instruction and not sung when the label is a recognized one on its own line | `[Verse]`, `[Chorus]`, `[Bridge]` |
| `[Section: descriptors]` | **Parameterized section override** — also read as instruction rather than sung, configures section behavior | `[Verse: piano only, no drums]` |
| `(text)` | **Vocal delivery modifier** — short cues (1-3 words) are interpreted as performance directives, triggering delivery changes (harmonies, whispers, echoes, ad-libs); longer phrases get sung as lyrics | `(whispered)`, `(echo)`, `(ad-lib: ooh)` |

Two conditions carry both bracket rows: a **recognized** label, **on its own line**. A **non-standard or verbose** label (`[Dubstep Drop]`, `[Emotional Moment]`) gets parsed as sung lyrics text, and so does any tag placed mid-line — see the recognized-label list above and [troubleshoot.md](troubleshoot.md). The parentheses row inverts the default: `(text)` is sung unless it is a short standard delivery directive.

Combine all three for arrangement-level precision:

```
[Chorus: full band, layered harmonies]
The night is calling (echoes)
The night is calling (whispered)
Take me home (ad-lib: home, home)
```

### Confidence note

Parameterized syntax is documented across multiple community guides (hookgenius, blakecrosley, jackrighteous). **No first-party Suno source states the `[Tag: descriptors]` form** — it is community-attested only. The full **per-section instrumentation control** as a primary technique (vs just vocal/mood modifiers) is community-validated through extensive empirical testing.

**MEDIUM confidence on the syntax** — multi-guide community consensus with no official Suno documentation, which is precisely what MEDIUM means in this skill's ladder; the "Performance shaping" section immediately below carries the same rung on the same kind of evidence. It was previously marked HIGH on the strength of a first-party citation that does not in fact describe bracket tags. MEDIUM on the broader "treat lyrics as second style channel" framing too. **The syntax itself is not in doubt — only the claim that Suno documented it.**

## Performance shaping (community-validated, MEDIUM confidence)

Well-attested across community guides and Reddit but not officially documented. Effects are real; exact magnitudes are folk wisdom.

| Technique | Syntax | Effect |
|-----------|--------|--------|
| **Capitalization** | `PRESSURE IS RISING` | Vocal pressure / grit / intensity spike. Use strategically on turning-point words; ALL-caps everywhere dilutes the effect |
| **Vowel stretching** | `looooove`, `shouuuuut` | Sustained notes, melisma. **3-5 extra vowels = natural; 20+ glitches** |
| **Ellipsis** | `and then... I realized` | Natural pause / breath (≈ 0.5-2 sec) |
| **Hyphenation** | `l-i-v-e the moment` | Staccato letter-by-letter delivery — good for rap or EDM emphasis |
| **Parenthetical cue** | `In the shadows (whispered)` | Inline performance directive. Keep 1-3 words; longer phrases get sung |
| **Line breaks** | One idea per line | Forces melodic separation; phrases on one line tend to run together. **A default, not a floor** — stacks of very short lines buy excess separation; see "Line breaks cut both ways" below |
| **Manual repetition** | Write the line twice with a tweak | `(x2)` notation is largely ignored — literal repetition with minor variation is more reliable |
| **Inline backing** | `I love you [ahhs rising]` | Adds layered backing vocals / inline FX |
| **Timing cue** | `[at 0:15 vocals enter]` | Reported to nudge timing; **no adherence rate is stated** — the old `~70%` had no basis. Less reliable than structure tags. LOW-MEDIUM; see `tips.md` "Timing cues" |

### Line breaks cut both ways — the short-line edge

"One idea per line" is the default because Suno phrases at every line break (row above). The same mechanism has a failure edge: **separation is what the break buys, so short lines buy too much of it.** A stack of clipped fragments can return with a pause after each one and a delivery that reads as choppy rather than sung. One mechanism, two directions.

**There is no established line-length floor**, and none is invented here — no source states a number. Judge it instead by whether each line is a phrase someone would sing in one breath: a clause holds, a fragment over-instructs. The one case observed here was a five-line bridge whose lines were fragments rather than clauses.

**The fix lives at the prompt layer, not in the lyric.** Join the lines that should sing as one phrase in the **Suno lyrics field**; the page lyric keeps its artistic lineation. These are two artifacts — the song, and the Suno input — and only the second one changes. Nothing here asks a writer to un-write a line.

**Basis.** The line-break mechanism carries this section's MEDIUM rung and is not rated down. The failure edge and the join fix are `writer-observed, single session (2026-08-12), n=1 — not externally corroborated` — one v5.5 session, one section, fixed on regeneration. What would settle it: the same section joined and un-joined across several generations each, plus one external report of the same edge. Diagnosis and fix steps: [troubleshoot.md](troubleshoot.md) "There's too much pause between lines".

## Hallucinated-lyrics prevention

Suno can't fix lyrics post-generation — prevention only. Apply these BEFORE generating:

- Use **clear punctuation** (commas, periods) — not run-on phrases
- Avoid **overly complex rhyme schemes** (internal multi-syllable rhymes confuse the model)
- Break **long sentences across lines**
- For **instrumental tracks**: use `[Melodic Instrumental]` AND include "instrumental" in style prompt
- **Pop and Gospel** are most vocal-prone genres — add explicit instrumental markers
- If lyrics field is **empty in Custom mode**, Suno may invent vocals — explicitly mark `[Instrumental]` or use Simple mode's instrumental toggle

## Best practices

- Keep total lyrics to **30-40 lines for a 3-4 min song** — past ~60 lines, delivery rushes or sections get skipped
- Match section count to song length: **2 verses + 2 choruses + 1 bridge** is safe default
- **One idea per line** — Suno breaks phrases at line endings. A default, not a floor: see "Line breaks cut both ways" for the short-line edge where it backfires and the prompt-layer join that fixes it
- Reuse the **chorus verbatim** (or near-verbatim) — repetition makes a hook stick. Write it out under **every** `[Chorus]`: a bare tag with no lyrics under it is not a reliable repeat instruction — see [troubleshoot.md](troubleshoot.md) "My bridge is missing / another section sang its lyrics"
- For multilingual songs: write the section in the target language; section tags themselves stay English
