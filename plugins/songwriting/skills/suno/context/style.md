# Style lane — full reference

The style/genre prompt tells Suno **what kind of song to make**. v5/v5.5 expanded this field from ~200 chars (v4) to ~1,000 chars, and adherence to nuanced descriptors improved dramatically. Treat the style prompt as a layered tag list, not a sentence.

## Character budgets (silent truncation)

| Field | Limit | Notes |
|-------|-------|-------|
| Style prompt (v5/v5.5) | **~1,000 chars** | Truncates silently — front-load critical content |
| Style prompt (v4 legacy) | ~200 chars | Out of scope for this skill, noted for orientation |
| Lyrics | **~3,000 chars** | ~40-60 lines / 200-300 words. Past 3K → Suno rushes, skips sections, or cuts output short |
| Title | **~80 chars** | No effect on musical output |
| Exclude (Custom mode Advanced Options) | Free-text box | Same vocabulary as inline negatives |

**Consensus verified 2026-05-10** across HookGenius, roo.beehiiv, musicsmith.ai — the earlier "5,000 lyrics" figure was a single-source outlier on one hookgenius v5.5 page (other hookgenius pages and the rest of the ecosystem agree on 3,000). The 5,000 figure may reflect API/programmatic context (chirp-crow model in ePhoneAI docs), not the UI lyrics field.

## The 6-layer formula

Order matters. Early tags are weighted more heavily.

### Layer 1 — Genre / subgenre

**Specific, not generic.** "pop" → generic AI sound. `synth-pop, 80s-inspired` → recognizable era and palette.

Good: `nu-disco`, `dream-pop`, `Nashville country`, `boom bap hip-hop`, `vapor-soul`, `Berlin minimal techno`, `bossa nova jazz`, `neo-soul`, `post-punk revival`, `K-pop ballad`

Hybrids work if intentional: `nu-metal dubstep`, `synthwave country`, `lo-fi neoclassical`. Avoid stacking 3+ genres — produces muddy output.

### Layer 2 — Mood

**2-3 related words.** "9-word mood lists" produce conflicting emotional signals.

Good: `nostalgic and hopeful`, `dark and brooding`, `euphoric, triumphant`, `melancholic, intimate`

Avoid: `happy sad angry triumphant melancholic dreamy aggressive contemplative joyful` (model picks at random)

### Layer 3 — Instrumentation

**Specific instruments, not categories.** "guitar" → unspecified. `fingerpicked nylon-string acoustic guitar` → exact texture.

| Generic (avoid) | Specific (use) |
|-----------------|----------------|
| guitar | fingerpicked acoustic guitar / palm-muted distorted electric / clean Telecaster / fuzz-tone fuzz bass |
| drums | brushed jazz drums / 808 trap drums / four-on-the-floor kick / breakbeat |
| bass | upright walking bass / Moog sub-bass / slap bass / fretless |
| synth | analog Moog pad / shimmering supersaws / glassy FM bell / wobble bass |
| piano | Rhodes electric piano / grand piano with felt damper / honky-tonk upright |

### Layer 4 — Vocal direction

**Acoustic descriptors, not value judgments.** "amazing vocals" → no effect. `breathy female vocals with slight rasp` → specific timbre.

Good: `breathy`, `raspy`, `intimate`, `belted`, `airy`, `warm`, `nasal`, `chesty`, `head-voice`, `falsetto`, `whispered`, `growled`, `polished`, `lo-fi`, `pitched-up`, `auto-tuned`, `dry`, `reverb-soaked`

Bad (zero effect): `amazing`, `epic`, `beautiful`, `incredible`, `perfect`, `stunning`

**v5.5 caveat:** when using Voices or Custom Models, **drop gender/tone descriptors entirely** — they conflict with the personalization layer.

### Layer 5 — BPM (numeric)

**Numbers beat descriptors.** Suno v5.5 hits ~90% accuracy on numeric BPM (vs ~70% in v4). Descriptors like "fast" drift ±20 BPM.

Syntax: `128 BPM`, `95 BPM`, `174 BPM`. Place after instrumentation/vocals, before production.

| Genre sweet spot | BPM |
|------------------|-----|
| Lo-fi / chill | 72 |
| R&B / soul | 78 |
| Hip-hop | 88 |
| Pop | 118 |
| Rock | 128 |
| Trap | 140 |
| Drum & bass | 174 |

### Layer 6 — Production / mix

The final layer paints the **acoustic environment** — what makes a track sound "polished" vs "lo-fi" vs "vintage".

| Style | Descriptors |
|-------|-------------|
| Lo-fi | `vinyl crackle, tape hiss, warm saturation, muffled drums` |
| Hi-fi | `crystal clear, polished mix, dynamic range, tight compression` |
| Vintage | `80s cassette warmth, analog tube saturation, reel-to-reel echo` |
| Modern | `ultra clean, spatial audio, hyper-compressed, sidechain pump` |

**Combinable:** `modern hi-fi with subtle vinyl crackle` works.

**Effect descriptors:**

- **Reverb / space**: `cathedral reverb`, `slapback delay`, `infinite tail`, `intimate room mic`, `plate reverb`, `spring reverb`
- **Compression / dynamics**: `heavy sidechain compression`, `subtle distortion on guitars`, `pumping bass`, `gated reverb`
- **Layering**: `layered whispers`, `filtered percussion swell`, `ambient pads underneath`
- **Tonal character**: `dusty`, `sub-bass`, `glassy`, `warm`, `analog warmth`, `gritty`, `polished`

## Tag count sweet spot

**5-8 distinct tags** is the working range:

- Fewer than 4 → output is generic
- 5-8 → coherent, recognizable style
- 10+ → conflicting signals, model picks and chooses, user loses control

## Negative prompts

Four equivalent syntaxes. **`no X` is most reliable and char-efficient.**

```
no vocals, no autotune, no reverb wash, dry mix
without drums, without synths
exclude electric guitar, exclude pad synths
avoid 4-on-the-floor kick
```

**Place negatives at the END of the style prompt.** Positives processed first, exclusions applied second. Mixing them mid-prompt weakens both.

**Exclude field (Custom mode Advanced Options):** a separate free-text box for unwanted elements. Use the same vocabulary. The Exclude field has stronger effect than inline negatives in some cases — try both if one fails.

**Highest-signal v5.5 negatives:**

- `no autotune` — pushes toward raw, organic vocals
- `no reverb wash` — pushes toward dry, present mix

**When negatives are ignored:**

- Pair with a positive (`piano only` is better than `no guitar`)
- Increase specificity (`no electric guitar` is better than `no guitar`)
- Cap at 2-3 negatives — stacking 5+ creates conflicts
- Switch to the Exclude field

## Key, time signature, groove

<!-- ordinal note-value notation in table trips the spell-checker --><!-- spellchecker:off -->
| Parameter | Syntax | Reliability |
|-----------|--------|-------------|
| Key | `key of D minor`, `A minor`, `Bb major` | Generally respected |
| Time signature | `4/4`, `3/4`, `7/8` in style prompt | Inconsistent — Studio supports editing but the generative model isn't yet wired to it |
| Groove / feel | `swing`, `shuffle`, `half-time`, `triplet feel`, `straight 8ths` | Effective |
<!-- spellchecker:on -->

## Working examples

**Pop:**

```
synth-pop, 80s-inspired, euphoric and nostalgic,
shimmering analog synths, warm Moog bass, punchy drum machine,
ethereal female vocals with reverb tail, 118 BPM,
polished radio-ready production, no autotune
```

Char count: ~210. Plenty of headroom.

**Indie folk:**

```
indie folk, fingerpicked acoustic guitar, warm upright bass,
sparse brushed drums, intimate female vocals with slight rasp,
94 BPM, key of D minor, vintage tube warmth,
no reverb wash, no synths, no drum machines
```

**Trap:**

```
trap hip-hop, deep 808 sub-bass, hi-hat rolls and triplets,
mumbling melodic flow, 140 BPM, F# minor,
sidechain on pads, modern hyper-compressed mix,
no live guitars, no acoustic instruments
```

## Iteration tips

- **Generate 4 versions** per prompt; A/B compare; refine one variable at a time
- **Reuse exact metadata** across regenerations to maintain vibe (`Track ID: lonelyrobot_v1, A minor, 95 BPM`)
- **Rotate synonyms** if regenerating produces diminishing returns: `gritty → raw → visceral → unpolished`
- **Audio Influence slider** (with upload) and **Style Influence slider** are your fine-tuning knobs in Custom mode — see [advanced.md](advanced.md)
