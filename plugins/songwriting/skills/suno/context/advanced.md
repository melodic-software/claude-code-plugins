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
| **Voices** (clone YOUR singing identity) | [voices.md](voices.md) — full guide | Pro / Premier; free plans got a **trial** on Aug 7 2026, possibly mobile-only — see [voices.md](voices.md) |
| **Custom Models** (fine-tune on your catalog) | [v55-features.md](v55-features.md#2-custom-models-fine-tune-on-your-catalog) | Pro / Premier |
| **My Taste** (passive preference learning) | [v55-features.md](v55-features.md#3-my-taste-passive-preference-learning) | All tiers |
| **Personas** (vibe templates from existing songs) | this file, below | All tiers |
| **Cover** (re-style preserving melody) | this file + [workflow-recipes.md](workflow-recipes.md#recipe-6-iterative-cover-chain) | All tiers |
| **Extend** (lengthen songs) | this file | All tiers |
| **Replace Section** (inpainting) | this file | Pro / Premier |
| **Upload Audio** (demo as seed) | [workflow-recipes.md](workflow-recipes.md#recipe-1-demo-upload--finished-track) | All tiers (size varies) |
| **Stems** (Split from Mix / Auto Split / Advanced Split) | [studio.md](studio.md#stem-isolation--export) | No stem separation on Free; Split from Mix + Auto Split on Pro+; Advanced Split Premier-only |
| **Suno Studio (GAW)** (multitrack DAW) | [studio.md](studio.md) — full guide | Premier |
| **Creative Sliders** (Weirdness, Style Influence, Audio Influence) | this file, below | Custom mode |
| **Duration slider** (target song length) | this file, below | Web + V5.5 model, in the Create form |
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

Suno's official help names these controls and their qualitative endpoints. **Every percentage, numeric range, and numeric default below is presented as community-empirical (MEDIUM confidence) — with one carve-out: the Audio Influence entry value is writer-observed, and carries its provenance in the note under the table.** No percentage here is an official recommendation; use the numbers as A/B-test starting points.

| Slider | Range | Default | Effect |
|--------|-------|---------|--------|
| **Weirdness** | Safe ↔ Chaos | 50% | Left = conventional structure / familiar progressions; right = unconventional / genre-bending |
| **Style Influence** | Loose ↔ Strong | 50% | Right = strict adherence to descriptors; left = creative interpretation |
| **Audio Influence** | (with upload only) | **25%** on entry to the cover-from-upload flow; other entry flows unobserved — see note below | Weight of uploaded reference vs creative AI interpretation |

**Audio Influence entry value — read the flow, not just the number.** The slider read **25%** on entry to the **cover-from-upload** flow (upload a file, then Cover it) on Suno v5.5. Provenance: `writer-observed, single session (2026-08-12), n=1 — not externally corroborated`, which sits off the [SKILL.md](../SKILL.md) confidence ladder rather than on a rung of it. First-hand does not mean stronger: this is one unreproduced reading.

**Do not generalize it across entry flows.** The **Extend** flow and the **upload-as-melodic-seed** flow were not observed, and nothing here establishes that Suno seeds them identically. Treat 25% as what you will see on a cover opened from an upload, and re-read the slider in any other flow rather than assuming a starting value.

**What the slider trades on a cover-from-upload.** Audio Influence is the fidelity-versus-freedom dial for anything built on an uploaded file. High = the uploaded **melody** is the shape the new style gets applied over. Low = the model is freer to build its own arrangement, and the melodic contour is the first thing it spends. Set it by what you are protecting:

- **Protecting the melody** — the demo's tune is the asset and you want a new production around it. Raise it well above the observed entry value. Cost: the target genre lands closer to a re-skin than a re-imagining, because the shape it must fit is already fixed. Suno publishes no number; `>=70%` circulates as a community-derived, unverified starting point — see [troubleshoot.md](troubleshoot.md).
- **Protecting the new arrangement** — you want the target genre to actually reshape the song. Leave it at or near the observed entry value. Cost: the melody can drift or be replaced, so what you liked about the demo may not survive the pass.
- **Undecided** — generate one pass near each end before committing. The two ends usually differ more than any middle value suggests.

The consequence of the observed entry value: on the one flow observed, a cover-from-upload opens **low**, so its untouched behavior is arrangement freedom, not melody fidelity. If the uploaded melody is the asset, that is a setting to change deliberately rather than inherit.

Community-empirical starting points:

- **Polished pop / radio-ready**: Weirdness ~30%, Style Influence ~75%
- **Genre-bending experimental**: Weirdness ~75%, Style Influence ~50%
- **Faithful upload extension**: Audio Influence ~80%, Style Influence ~70%

## Duration slider (Create form)

**Added after this skill's v5.5 baseline.** Suno's release notes, Jul 20 2026: *"Drag the new Duration slider in the Create form to pick your song length. Available on Web using V5.5 model."* — tagged *Improvement, CREATE, WEB* (<https://suno.com/release-notes/duration-slider-on-web>, fetched 2026-08-12). **HIGH confidence** for the control's existence, its name, its home in the Create form, and that platform scoping. Everything below that line is weaker and says so.

**The platform scoping is first-party and narrow.** The entry carries `WEB` and no mobile tag, and no later release note through 2026-08-12 brings the slider to iOS or Android. Treat it as web-only until a release note says otherwise.

| Detail | Value | Basis |
|--------|-------|-------|
| Where | Create form | First-party release note above |
| Model | V5.5 | First-party release note above |
| Platform | Web; no mobile tag | First-party release note above |
| Range | 10 seconds to 6 minutes | **LOW-MEDIUM** — see below |
| Increment | 5 seconds | **LOW-MEDIUM** — one community post |
| Default | Auto (Suno picks the length); Custom engages the slider | **LOW-MEDIUM** — one community post |

**The range is attested twice, from two different directions, and still only reaches LOW-MEDIUM.** It was read off the UI first-hand (`writer-observed, single session (2026-08-12)`) and is independently stated as "10 seconds to 6 minutes, in 5-second increments" by one community post ([a v5.5 duration-control guide](https://note.com/dreammii/n/n6e7cf9fc2ace), fetched 2026-08-12) — so unlike most writer-observed items in this skill it is **not** uncorroborated. It stays LOW-MEDIUM anyway: no `help.suno.com` article states a range. The two length-related help articles both predate the slider and cover per-model maximums and Extend instead (<https://help.suno.com/en/articles/2409473>, <https://help.suno.com/en/articles/2409601>), and two published guides written *about* the slider decline to state a range or increment at all. Treat the numbers as what the UI is reported to offer, not as published limits.

**The slider's Auto/Custom setting is not Suno's Simple/Custom generation mode.** Two unrelated uses of the word — do not conflate them.

**A selected duration is a target, not a guarantee** — *"not a guarantee that Suno will end on an exact second"* ([Jack Righteous song-length guide](https://jackrighteous.com/en-us/blogs/guides-using-suno-ai-music-creation/suno-duration-slider-song-length-guide), fetched 2026-08-12). Record the runtime you actually got rather than assuming the slider value.

**OPEN QUESTION — what a duration target does to a lyric that does not fit it.** Unresolved as of 2026-08-12; **do not advise on this until it is settled.** The single community post above reports a hard cut rather than a fade when the target is reached, rushed delivery when a long lyric meets a short target, and trailing silence when the target overruns the lyric. Nothing first-party addresses it and both guides written about the slider explicitly do not. The direction is plausible because this skill already documents the same failure family from the other end — past ~3,000 lyric chars Suno "rushes, skips sections, or cuts output short" — but **a shared failure shape is not evidence that the slider causes it.** Settle it by generating one lyric against a short and a long target and recording both runtimes.

**Recheck trigger:** any `help.suno.com` article on the Duration slider, or a release note extending it beyond Web / V5.5.

## More Options panel (Custom mode)

The "More Options" expandable section contains five controls. Claims below are community-empirical unless explicitly identified as first-party; numeric thresholds are MEDIUM-confidence starting points. **The Duration slider is not one of the five** — the Jul 20 2026 release note places it in the Create form, and no source places it inside this panel, so the count above stands. See [Duration slider (Create form)](#duration-slider-create-form).

### Exclude styles (text field)

Operates at **different parsing stage** than inline `no X` negatives — Suno's negative-constraint pipeline vs style-prompt mixed pipeline. **More reliable than inline negatives** for global removal.

**Convention: enter BARE NOUNS, not negation phrases.** This is the documented convention, not a demonstrated requirement. Suno's own instruction for the field is first-party — "Enter any information (instruments, etc) that you do not want in your track" (`help.suno.com/en/articles/3161921`) — and community worked examples for the field list bare nouns. **No source shows negation phrases failing.**

| Convention | Off-convention |
|------------|----------------|
| `drums` | `no drums` |
| `synthesizers, autotune` | `without synthesizers, no autotune` |
| `electric guitar` | `exclude electric guitar` |

The field is already negative, so "no" / "without" / "exclude" are redundant inside it. What the parser does with them is untested — use the bare-noun column because it is the attested form, not because the other column is known to be ignored.

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

The following percentages are community-empirical, not official thresholds:

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

### Weirdness slider (community-empirical numeric guidance)

Community-empirical sweet spot: **60-65% for distinctive output that maintains coherence**. The 50% baseline used here is also treated as community-empirical.

| Range | Output character | Use case |
|-------|------------------|----------|
| 0-25% | Formulaic, radio-safe | Protect-the-chorus during section replacement |
| 26-49% | Conservative mainstream | Mainstream pop / country / hip-hop |
| 50% | Balanced default | First-pass exploration |
| **60-65%** | **Professional-sounding, artistically distinctive** | **Jazz, indie, electronic, alternative — community sweet spot** |
| 75-85% | Experimental, risky | Genre-bending, intentional weirdness |
| 86%+ | Chaos, rarely usable | A/B sanity check only |

**Community-empirical protect-the-chorus principle:** when using Replace Section to swap a chorus, try Weirdness at 25-40% to preserve the established hook character. Push higher in bridges where contrast is welcome.

### Style Influence slider (community-empirical numeric guidance)

| Range | Effect |
|-------|--------|
| <25% | Style prompt nearly ignored — output drifts genre |
| 40-55% | Balanced iteration starting point |
| 65-80% | Strict genre adherence (mainstream pop, country, classical) |
| 85%+ | Diminishing returns, repetitive, over-fits to descriptors |

**Community-empirical inverse interaction with Weirdness:** high Weirdness + high Style Influence may create incoherent competition.

Community testers coordinate the sliders as **balanced opposition:**

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
