# Advanced features — index

Suno v5.5 has multiple generation modes, post-generation tools, and personalization layers. This is the **index** — each feature links to its dedicated guide.

## Mode selector

| Mode | Workflow | When to use |
|------|----------|-------------|
| **Simple** | One unified description; auto-generates lyrics + style | Rapid prototyping, casual creation |
| **Custom** | Separate fields (style, lyrics, title) + Advanced Options | Production work, tag syntax, all features below |

**Custom mode is required for:** structural tags, vocal direction tags, parameterized `[Tag: descriptor]` syntax, the Exclude field, Creative Sliders, voice selection, persona selection.

## Feature index

| Feature | Where to find it | Tier |
|---------|------------------|------|
| **Voices** (clone YOUR singing identity) | [voices.md](voices.md) — full guide | Pro / Premier |
| **Custom Models** (fine-tune on your catalog) | [v55-features.md](v55-features.md#2-custom-models-fine-tune-on-your-catalog) | Pro / Premier |
| **My Taste** (passive preference learning) | [v55-features.md](v55-features.md#3-my-taste-passive-preference-learning) | All tiers |
| **Personas** (vibe templates from existing songs) | this file, below | All tiers |
| **Cover** (re-style preserving melody) | this file + [workflow-recipes.md](workflow-recipes.md#recipe-6-iterative-cover-chain) | All tiers |
| **Extend** (lengthen songs) | this file | All tiers |
| **Replace Section** (inpainting) | this file | Pro / Premier |
| **Upload Audio** (demo as seed) | [workflow-recipes.md](workflow-recipes.md#recipe-1-demo-upload--finished-track) | All tiers (size varies) |
| **Stems** (2-track / 12-track export) | [studio.md](studio.md#stem-isolation--export) | 2-track all / 12-track Pro+ |
| **Suno Studio (GAW)** (multitrack DAW) | [studio.md](studio.md) — full guide | Premier |
| **Creative Sliders** (Weirdness, Style Influence, Audio Influence) | this file, below | Custom mode |
| **ReMi** (lyric-generation model) | this file, below | All tiers |

## Personas (distinct from Voices)

A **Persona** captures the **essence of an existing generated song** — vocal character, energy, atmosphere — and makes it reusable.

- Created via song action menu → "Make Persona"
- Reusable as vibe template across new prompts
- Public or private toggle
- Available in Custom mode under voice/style selector
- **Persona ≠ Voice**: Voice is YOUR singing identity; Persona is a song-level vibe template

## Cover

Re-styles an existing song while preserving melody.

- Chainable: cover → cover-of-cover → ...
- Each version traces back to original
- **Commercial use:** OK on YOUR originals; NOT OK on someone else's track
- See [workflow-recipes.md](workflow-recipes.md#recipe-6-iterative-cover-chain) for the chain pattern

## Extend

Lengthen a song from a chosen preservation point.

1. Drag the white arrow on the waveform to where the original ends
2. Add new lyrics and/or style for the continuation
3. Generate; Suno extends from that point
4. **"Get Whole Song"** stitches original + extension into a seamless track

Tip: use a structural tag (`[Bridge]`, `[Outro]`, `[Final Chorus]`) in the extension lyrics to guide section type.

## Replace Section (Inpainting)

**Pro / Premier only.** Edit a mid-song section without regenerating the whole track.

1. Click-and-drag to highlight the section to replace
2. Edit lyrics on the left; original highlighted on the right
3. Toggle **"Make Same Length as Section"** off if you want a longer solo / break
4. Generate — produces 2 alternates
5. Select preferred → produces a new whole song

Fix for "the second verse is bad but the rest is perfect."

## Creative Sliders

| Slider | Range | Default | Effect |
|--------|-------|---------|--------|
| **Weirdness** | Safe ↔ Chaos | 50% | Left = conventional structure / familiar progressions; right = unconventional / genre-bending |
| **Style Influence** | Loose ↔ Strong | 50% | Right = strict adherence to descriptors; left = creative interpretation |
| **Audio Influence** | (with upload only) | — | Weight of uploaded reference vs creative AI interpretation |

Practical defaults:

- **Polished pop / radio-ready**: Weirdness ~30%, Style Influence ~75%
- **Genre-bending experimental**: Weirdness ~75%, Style Influence ~50%
- **Faithful upload extension**: Audio Influence ~80%, Style Influence ~70%

## More Options panel (Custom mode)

The "More Options" expandable section contains five controls. Empirical detail on each (HIGH confidence, multi-source community testing).

### Exclude styles (text field)

Operates at **different parsing stage** than inline `no X` negatives — Suno's negative-constraint pipeline vs style-prompt mixed pipeline. **More reliable than inline negatives** for global removal.

**Critical syntax: enter BARE NOUNS, NOT negation phrases.**

| Correct | Wrong (silently ignored) |
|---------|--------------------------|
| `drums` | `no drums` |
| `synthesizers, autotune` | `without synthesizers, no autotune` |
| `electric guitar` | `exclude electric guitar` |

The field already negates. Adding "no" / "without" / "exclude" creates a double-negative the parser drops.

**Complex exclusions like "no drums except cymbals" fail in this field** — handle via per-section style overrides in the lyrics field instead (see [lyrics.md](lyrics.md)).

**Division of labor:**

- **Exclude styles field** = global removal (entire song)
- **Per-section overrides in lyrics** = section-scoped exclusions (`[Verse: piano only, no drums]`)
- **Style prompt** = positive descriptors only (don't put negatives here when Exclude field is available)

### Vocal Gender (Male / Female toggle)

When **set**, the toggle **overrides contrary text** in the style prompt — operates at synthesis pre-text-parsing stage, so toggle wins any conflict.

When **unspecified** (neither selected), the model **infers** from genre conventions:

- "energetic pop" → likely female
- "soulful blues" → likely male
- "ambient electronic" → ambiguous

Inference is **unreliable** — explicitly set the toggle when you care.

**Conflict with active Voices:** setting the toggle while using a Voice produces gender-shifted derivatives of the Voice timbre (artifacts). **Leave the toggle unspecified when using a Voice.**

**Interaction with Style Influence:**

- At SI ≥80%, the toggle's impact diminishes (style descriptors dominate)
- At SI 40-50%, the toggle dominates over text descriptors
- **Best practice:** explicit toggle + complementary descriptor in style prompt + SI 65-75%

### Lyrics Mode (Manual / Auto toggle)

**Quality gap is substantial — described as "approaching a full model-version difference."**

| Mode | Behavior |
|------|----------|
| **Manual** | Your typed lyrics respected; **parameterized metatags work**; section markers reliable; vocal modifiers (`[Whisper]`, `[Belted]`, `[Falsetto]`) honored |
| **Auto** | Suno generates lyrics from style prompt + intent; **brackets ignored entirely** (treated as literal text or undifferentiated sequence) |

**Auto only acceptable for:**

- Short experimental loops
- Starter templates you'll then refine in Manual
- Pure instrumentals where lyrics field is unused

**Default rule:** Auto in Simple Mode, **Manual in Custom Mode** for anything production-grade.

### Weirdness slider (default 50%)

Community sweet spot: **60-65% for distinctive output that maintains coherence** (not the default 50%).

| Range | Output character | Use case |
|-------|------------------|----------|
| 0-25% | Formulaic, radio-safe | Protect-the-chorus during section replacement |
| 26-49% | Conservative mainstream | Mainstream pop / country / hip-hop |
| 50% | Balanced default | First-pass exploration |
| **60-65%** | **Professional-sounding, artistically distinctive** | **Jazz, indie, electronic, alternative — community sweet spot** |
| 75-85% | Experimental, risky | Genre-bending, intentional weirdness |
| 86%+ | Chaos, rarely usable | A/B sanity check only |

**Protect-the-chorus principle:** when using Replace Section to swap a chorus, drop Weirdness to 25-40% — preserves the established hook character. Push higher in bridges where contrast is welcome.

### Style Influence slider (default 50%)

| Range | Effect |
|-------|--------|
| <25% | Style prompt nearly ignored — output drifts genre |
| 40-55% | Balanced iteration starting point |
| 65-80% | Strict genre adherence (mainstream pop, country, classical) |
| 85%+ | Diminishing returns, repetitive, over-fits to descriptors |

**Inverse interaction with Weirdness:** high Weirdness + high Style Influence = incoherent competition (model fights itself).

Coordinate as **balanced opposition:**

- Weirdness 65-75% + Style Influence 55-70% — distinctive but coherent
- Weirdness 30-40% + Style Influence 75-85% — polished and on-genre
- Weirdness 50% + Style Influence 50% — exploratory default

## ReMi (lyric-generation model)

Beta lyric model accessed via "Write with Suno" dropdown in Custom mode.

- **Classic** model: standard lyric generation
- **ReMi**: edgier, less polished, more experimental
- All tiers (no Pro requirement)
- Use for: rap / punk / metal where polished pop lyrics feel wrong; first-draft generation that you'll edit

## Where to go from here

| Need | File |
|------|------|
| Train a Voice and use it without conflicts | [voices.md](voices.md) |
| Edit / rearrange / add instruments to existing songs | [studio.md](studio.md) |
| End-to-end workflow recipes (demo → finished track) | [workflow-recipes.md](workflow-recipes.md) |
| What's specifically new in v5.5 | [v55-features.md](v55-features.md) |
| Lookup an artist / song / current trend | [research-recipes.md](research-recipes.md) |
