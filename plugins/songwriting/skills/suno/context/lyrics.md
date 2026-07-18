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

### Recognized core section labels (HIGH reliability in v5.5)

Use ONLY these labels for structural section tags. Non-standard labels (`[Hook Variation]`, `[Synth Solo]`, `[Final Push]`) get parsed as sung lyrics text, not structure.

```
[Intro] [Verse] [Verse 1] [Verse 2] [Verse 3]
[Pre-Chorus] [Chorus] [Hook] [Post-Chorus] [Refrain]
[Bridge] [Break] [Breakdown] [Build] [Build-Up]
[Drop] [Interlude] [Instrumental] [Instrumental Break]
[Outro] [End] [Fade Out] [Fade In]
```

For solos use `[Guitar Solo]`, `[Piano Solo]`, `[Drum Solo]`, `[Bass Solo]`, `[Saxophone Solo]`, `[Synth Solo]` — these are recognized.

For anything else, **describe via parameterized syntax** instead of inventing a new label:

- Want a "synth solo": use `[Instrumental Break: synth solo, layered leads, 8 bars]` not `[Synth Solo Variation]`
- Want a "hook variation": use `[Chorus: stripped down, key change up a step]` not `[Hook Variation]`

### When per-section overrides get ignored

- **Section override contradicts global style** — global says `electronic dance`, override says `acoustic guitar only` → model picks one. Section overrides should be **specific instantiations** of global style, not wholesale contradictions
- **Too many overrides per section** — 8+ modifiers compete. Cap at 7 (sweet spot 4-7)
- **Override placed on wrong line** — must be on the `[Tag]` line itself, not on a lyric line below
- **Ambiguous descriptors** — `[Verse: better]` does nothing. Be specific: `[Verse: piano only, no drums]`
- **Lyric density mismatch** — `[Verse: piano only]` paired with 8 lines of dense lyrics gets ignored — model fills sonic space to support the vocal load. Either (a) shorter lyrics for sparse arrangements, or (b) more sonic descriptors to convince the model
- **v4.5-era metatag formats** — `[Female Vocal]`, `[Whisper]`, `[Choir]` as structural tags broke in v5.5. Migrate to colon-descriptor form: `[Vocalist: Female]` or use parameterized section: `[Verse: female vocal, whispered, intimate]`. Plain section tags like `[Verse]`/`[Chorus]` still work standalone

### Brackets vs Parentheses — the v5.5 distinction

| Syntax | Purpose | Example |
|--------|---------|---------|
| `[Section]` | **Structural label** — boundary marker, never sung | `[Verse]`, `[Chorus]`, `[Bridge]` |
| `[Section: descriptors]` | **Parameterized section override** — also never sung, configures section behavior | `[Verse: piano only, no drums]` |
| `(text)` | **Vocal delivery modifier** — never sung as text BUT triggers delivery changes (harmonies, whispers, echoes, ad-libs) | `(whispered)`, `(echo)`, `(ad-lib: ooh)` |

Combine all three for arrangement-level precision:

```
[Chorus: full band, layered harmonies]
The night is calling (echoes)
The night is calling (whispered)
Take me home (ad-lib: home, home)
```

### Confidence note

Parameterized syntax is documented across multiple community guides (hookgenius, blakecrosley, jackrighteous) and confirmed by Suno's own "Song Editor" article (`help.suno.com/en/articles/6141505`). The full **per-section instrumentation control** as a primary technique (vs just vocal/mood modifiers) is community-validated through extensive empirical testing — HIGH confidence on syntax, HIGH-MEDIUM on the broader "treat lyrics as second style channel" framing.

## Performance shaping (community-validated, MEDIUM confidence)

Well-attested across community guides and Reddit but not officially documented. Effects are real; exact magnitudes are folk wisdom.

| Technique | Syntax | Effect |
|-----------|--------|--------|
| **Capitalization** | `PRESSURE IS RISING` | Vocal pressure / grit / intensity spike. Use strategically on turning-point words; ALL-caps everywhere dilutes the effect |
| **Vowel stretching** | `looooove`, `shouuuuut` | Sustained notes, melisma. **3-5 extra vowels = natural; 20+ glitches** |
| **Ellipsis** | `and then... I realized` | Natural pause / breath (≈ 0.5-2 sec) |
| **Hyphenation** | `l-i-v-e the moment` | Staccato letter-by-letter delivery — good for rap or EDM emphasis |
| **Parenthetical cue** | `In the shadows (whispered)` | Inline performance directive. Keep 1-3 words; longer phrases get sung |
| **Line breaks** | One idea per line | Forces melodic separation; phrases on one line tend to run together |
| **Manual repetition** | Write the line twice with a tweak | `(x2)` notation is largely ignored — literal repetition with minor variation is more reliable |
| **Inline backing** | `I love you [ahhs rising]` | Adds layered backing vocals / inline FX |
| **Timing cue** | `[at 0:15 vocals enter]` | ~70% adherence — less reliable than structure tags |

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
- **One idea per line** — Suno breaks phrases at line endings
- Reuse the **chorus verbatim** (or near-verbatim) — repetition makes a hook stick
- For multilingual songs: write the section in the target language; section tags themselves stay English
