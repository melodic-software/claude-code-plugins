# Power-user tips & undocumented techniques

Techniques here are community-reported and **not Suno-documented**. Exact magnitudes vary by prompt.

**Confidence is per section, not per file** — read the flag on the section you are using. This file's blanket "community-validated through empirical testing" header was removed in 1.1.2: it asserted validation the file cannot back, while two sections inside it are explicitly flagged unverified. A section carrying no flag has not been audited.

Pair with `tips.md` (lyric-side performance tricks) and `lyrics.md` "Per-section style overrides" (lyrics-as-second-style-channel technique).

## Tag order

**The two halves of this rule now have different standing.** The r/SunoAI pass that 1.1.3 said could not run **did run**, via the browser route, on 2026-08-12. It sources one half at the bottom rung and leaves the other exactly where it was.

- **Front-loading — now community-attested at LOW-MEDIUM.** An upvoted r/SunoAI guide post, [*"Expanded Insight and Guidance on Suno Style Prompt Writing"*](https://www.reddit.com/r/SunoAI/comments/1h4zc7e/expanded_insight_and_guidance_on_suno_style/) (13 votes, 28 comments), leads with **"Key Insight 1: Order Matters"** and states that Suno assigns importance by order, that the first descriptors set the stage while later ones add flavor, and that you should put the most crucial element first. It gives a paired optimized/less-effective example differing **only** in which half leads. Read by eye from the rendered page on 2026-08-12.

  **LOW-MEDIUM, not MEDIUM** — and the rung is the ladder's, not a judgment call. `SKILL.md` defines LOW-MEDIUM as *"at most a single community post plus its own comment thread"*, which is exactly what this is: **one** post. MEDIUM needs multiple guides **plus** Reddit consensus, and no second independent source states per-tag weighting — the first-party beat article speaks to category order, not tag weight, and the v4.5 help article points away from prioritized tokens. This is a genuine upgrade from 1.1.1's *"never checked in either direction"*, and it stops there.
- **Middle-tag softening (roughly 4-7) — still unsourced, in either direction.** The post above says nothing about middle positions, and nothing else found does either. This half stays an untested rule of thumb; do not let the sourcing of the first half carry it.
- **Grouping negatives at the end is an organizational convention.** No source establishes that end-placement changes exclusion weight; the `no X` syntax itself is community-attested. Searched for directly: no source addresses placement at all.

**Era caveat, and it is load-bearing.** That post is from 2024 (v3/v4 era). Suno's own [help.suno.com 5782849](https://help.suno.com/en/articles/5782849) says of v4.5 that *"In previous models, you would want to prioritize certain genre and style details, but your instructions can now include a more conversational prompt."* First-party guidance is therefore moving **away** from the terse prioritized-token style the front-loading rule is about. Treat front-loading as attested for the terse comma-separated form and **unverified for v5.5 conversational prompts**, which is what this skill targets.

Practical: if mood matters more than genre for a specific song, lead with mood. If a single instrument is the song's signature, name it before the genre. Cheap to try.

**Also first-party on ordering:** [how-to-make-beats](https://suno.com/hub/how-to-make-beats), fetched 2026-08-12 — Suno *"reads prompts as structured instructions. A clear hierarchy matters … A strong prompt follows this order: tempo, genre, rhythm style, instruments, and mood."* That prescribes an ordering of descriptor **categories** and is scoped to beat-making, so it corroborates "order is meaningful" without speaking to per-tag weight.

**Recheck trigger:** Suno documents style-prompt ordering for v5 or later, **or** an r/SunoAI thread dated to the v5.x era tests front-loading on conversational prompts, **or** a re-read finds the cited post no longer carrying its Key Insight 1. Not a date.

## Genre fusion — anchor and accent

**What is attested is a hierarchy.** Give one genre the lead and let the second supply texture; do not bill two genres equally. All three sources below say this.

**Position remains unestablished. One anecdote does not change that.** The 2026-08-12 r/SunoAI pass found a user reporting a bare order swap — in [*"Style order"*](https://www.reddit.com/r/SunoAI/comments/1g5qzes/style_order/), that `progressive metal, jazz` and `jazz, progressive metal` gave noticeably different results, the first heavier and more prog.

**It varies the right variable but cannot measure the effect, and this skill's own guidance says why.** `tips.md` "Generate 4 versions per prompt" states *"Variance is high. First generation is rarely best."* Against a stochastic generator, one run per ordering leaves run-to-run variance as an uncontrolled confounder: two different outputs are exactly what you would expect from the *same* prompt twice. Isolating position needs repeated or seed-controlled comparison, which nobody has published. The same thread's other reply says merged styles need no particular order.

So: **a hypothesis with a clean design and no power behind it.** Recorded as an anecdote and as the shape a real test would take — not as evidence. The old wording "Order encodes priority" stays out, and prefer the hierarchy framing below, which independent sources do support.

```
synth-pop with dream-pop textures
```

vs

```
dream-pop with synth-pop production
```

These are expected to produce **different outputs** — but note *what* differs. The lead genre is the noun the track **is**; the accent is a thing the track **has**. Grammatical role is the signal the guides describe explicitly, and word order moves with it here. **This example cannot separate the two**, because it changes both at once — so use it as an illustration of anchor/accent, never as evidence about position. The comma-swap report above varies position alone but, as noted, has no power behind it, so **no source here isolates position with evidence**.

**Three or more genres with no hierarchy degrades the result** — sources describe mush, averaging, and drift. The former "hard cap: 2" was this file's own sharpening; two sources model exactly one anchor plus one accent, a third warns against "three-way competition", and none states a numeric cap. Treat two as the working default and anything beyond as needing an explicit hierarchy, not as a hard limit.

**Still between LOW-MEDIUM and MEDIUM — but now because the Reddit pass ran, not because it could not.** `SKILL.md` defines MEDIUM as multiple community guides **plus** Reddit consensus. Three independent guides give the first half. The 2026-08-12 r/SunoAI pass found **one** corroborating post (its "first descriptors set the stage, later ones add flavor" is the same stage/flavor hierarchy) and one thread split on bare order — corroboration, not consensus. One post is the ladder's own LOW-MEDIUM ceiling, so the Reddit clause is **still unmet**, and the section is not rounded up.

What changed is the basis, not the rung: 1.1.2 and 1.1.3 rated this down for an *untried* corpus, which was wrong twice over — the corpus was reachable, and the pass now says something specific. Surface as an opt-in suggestion, not a default.

1.1.2 and 1.1.3 recorded the Reddit half as unmet and untried on the belief that `reddit.com` was unreachable. **It was reachable the whole time** — via the browser route this plugin's own `workflow-recipes.md` already documented. The gap was an unread in-repo note, not a blocked corpus.

Verified 2026-08-12; each web page below fetched live by `curl` (bodies arrived whole; character counts are of the extracted text, quotes verbatim), each Reddit thread read by eye from the rendered page.

- [sunopromptpro.com/en/guides/suno-genre-combinations](https://www.sunopromptpro.com/en/guides/suno-genre-combinations) (7,086 chars) — *"A genre combination should not give every style equal authority. Start with the lane that should control the song shape"*; and *"Avoid three-way competition. Most hybrid prompts become weaker when they name three or four genres with no hierarchy."*
- [brahmstorm.com/blog/suno-genre-blending-prompts-that-actually-work](https://brahmstorm.com/blog/suno-genre-blending-prompts-that-actually-work/) (8,741 chars) — *"pick ONE dominant genre as the anchor … then add ONE accent genre"*; and, **qualifying** rather than refuting the positional reading, *"The cleanest way to signal hierarchy is through sentence structure, not just word order."*
- [jackrighteous.com — Suno prompt too complicated](https://jackrighteous.com/en-us/blogs/guides-using-suno-ai-music-creation/suno-prompt-too-complicated-clean-workflow) (22,431 chars) — *"Blending Genres Requires a Hierarchy … The problem begins when every genre is treated as an equal foundation."*
- r/SunoAI [*"Expanded Insight and Guidance on Suno Style Prompt Writing"*](https://www.reddit.com/r/SunoAI/comments/1h4zc7e/expanded_insight_and_guidance_on_suno_style/), 13 votes / 28 comments — "Key Insight 1: Order Matters"; first descriptors set the stage, later ones add flavor. **2024, v3/v4 era.**
- r/SunoAI [*"Style order"*](https://www.reddit.com/r/SunoAI/comments/1g5qzes/style_order/), 1 vote / 2 comments — a single-run comma-swap anecdote, **and** a reply asserting no particular order is needed. Cited for the split and for the test design it suggests, not for a verdict.

**Not officially documented.** `help.suno.com` articles [5782849](https://help.suno.com/en/articles/5782849) (1,177 chars, whole) and [5782977](https://help.suno.com/en/articles/5782977) (805 chars, whole) were read verbatim on 2026-08-12 and neither addresses genre order or fusion; 5782849 points the other way for v4.5+, saying *"In previous models, you would want to prioritize certain genre and style details, but your instructions can now include a more conversational prompt."* That absence is scoped to those two pages, not to Suno's documentation as a whole.

**Recheck trigger:** Suno's help center or blog publishes guidance on style-prompt ordering or genre blending; **or** a second independent community source states genre-order weighting, which would meet the ladder's Reddit-consensus clause; **or** anyone publishes a repeated or seed-controlled order comparison, which would settle the position question the anecdote above cannot; **or** a read-time re-fetch finds any source above no longer carrying its quoted text. Not a date.

## Stem-loop refinement (Premier)

Surgical refinement of a single instrument layer without losing the rest:

1. Generate full song
2. **Auto Split stem export** (up to 12 stems; Pro / Premier)
3. Upload ONE stem back as Audio Influence at 80% (community-derived starting point; not officially confirmed)
4. Prompt narrowly for that element only (`punchy 808 trap drums, no other elements`)
5. Regenerate

Result: targeted layer regenerates cleaner; rest of mix preserved when you re-comp in Studio.

## Two-pass vocal isolation

Cleaner vocal separation than single-pass generation:

**Pass 1 — instrumental only:**

- Lyrics field: `[Melodic Instrumental]`
- Style prompt: target arrangement + `instrumental, no vocals` at end

**Pass 2 — vocals over Pass 1:**

- Upload Pass 1's audio
- Audio Influence ~80% (community-derived starting point; not officially confirmed)
- Style prompt: vocal-only descriptors (`female vocals, breathy, intimate`)
- Lyrics field: full song lyrics with section tags

Output: instrumental + isolated vocal. Trivial to remix or mute either side in external DAW.

## Persona-as-draft-mode

Cheap iteration before committing to final Custom prompt:

1. Save a known-good song as Persona ("Make Persona" from song menu)
2. Generate 4-8 drafts with Persona + minimal new prompt — fast, low effort
3. Use drafts to test ARRANGEMENT ideas (verse/chorus pacing, bridge placement)
4. Lock the arrangement you like
5. Regenerate that arrangement with FULL Custom prompt (precise instrumentation, mood, production layers) for the production take

Personas trade fidelity for speed; full Custom mode trades speed for fidelity. Use both.

## Punctuation for vocal cadence

| Mark | Effect | Approx duration |
|------|--------|-----------------|
| `,` | Small breath / pause | ~0.3s |
| `.` | Full stop pause | ~0.7s |
| `—` (em dash) | Held note / sustain | varies |
| `…` (ellipsis) | Natural breath / contemplative pause | 0.5-2s |
| `!` | Emphasis spike on preceding word | — |
| `?` | Rising inflection on final word | — |
| Newline | Melodic boundary / phrase end | — |
| `(parenthetical)` | Inline performance directive | — |

Use punctuation as **rhythm notation**, not just orthography. A line with no commas runs together; a line with three commas breathes.

## Bracket-only structural gaps

Counter the AI tendency to cram lyrics wall-to-wall. Insert deliberate breathing room:

```
[Verse 1]
First narrative beat
Second line landing the image

[8 bars]

[Pre-Chorus]
Tension building...
```

Or describe the gap:

```
[Instrumental Break: drums solo, building intensity]
[Breakdown: bass and synth pad only, 4 bars]
[Silence: 2 seconds before drop]
```

The model skips empty space if you don't ask for it. Asking deliberately produces dynamic contrast.

## Genre-adjacency fallback

If a specific subgenre tag doesn't trigger (output is generic), use a near-neighbor well-trained genre + descriptor:

| Specific (might miss) | Adjacency fallback |
|-----------------------|--------------------|
| `vapor-soul` | `neo-soul with vaporwave production` |
| `jersey club` | `bounce house with sliding 808s` |
| `slowcore` | `indie rock, slowed and somber, sparse production` |
| `phonk` | `Memphis hip-hop with distorted 808s and cowbell` |
| `dungeon synth` | `lo-fi medieval keyboard textures, melancholic and mythic` |
| `gqom` | `South African house with broken minimal beats, dark mood` |
| `witch house` | `dark electronic with chopped vocals and gothic atmosphere` |
| `hyperpop` | `pitched-up vocals with maximalist production and glitchy synths` |

The neighbor anchors the model in known territory; the descriptor pulls toward the target.

## The "describe THIS song" technique

For a specific reference song, describe what you HEAR rather than naming artist or song. Higher fidelity than artist-name workarounds.

**Method:**

1. Listen to the reference (or pull facts from research)
2. Break it down per section
3. Describe instrumentation + vocal + production per section
4. Use per-section overrides in lyrics field

**Example reference: "Mr. Brightside" by The Killers (don't name it):**

Style prompt:

```
2000s indie rock, anthemic and driving, jangly clean Telecaster,
bouncing 16th-note hi-hats, melodic male tenor, 148 BPM,
key of D-flat major, polished radio production with vintage warmth
```

Lyrics field with section overrides:

```
[Intro: bass + hi-hats, building]
[Verse 1: clean guitar arpeggios, restrained drums, conversational vocal]
[Chorus: full band kicks in, layered guitars, anthemic backing vocals]
[Bridge: stripped to vocal + reverb-soaked guitar, vulnerable]
[Final Chorus: explosive, gang vocals, double-tracked]
```

Beats `like The Killers` (filtered) AND beats generic `2000s indie rock`. Specificity wins.

## Empirical Custom Model trick

Train Custom Model on YOUR own reference catalog of songs you LOVE the sonic DNA of (must own — 6+ tracks):

- Style tags now operate relative to YOUR baseline, not generic averages
- Effectively produces "songs that sound like ME but new"
- Especially powerful when your catalog is sonically coherent (same genre, similar production)

**Critical: train separate models per coherent sound.** A model trained on lo-fi + thrash metal in the same set averages into incoherent middle-ground. Train one Custom Model per sonic identity.

**Combine with Voices for the full identity stack:**

- Custom Model = your sonic DNA (production, instrumentation patterns)
- Voice = your singing identity (vocal timbre)
- Both active = "you wrote, produced, AND sang this" output

## Bonus: rotating prompt synonyms across regenerations

After 3-4 regenerations on identical prompt, output diminishes (cached patterns). Rotate synonyms to break the loop without changing intent:

| Stuck on | Try rotating to |
|----------|-----------------|
| `gritty` | `raw` → `visceral` → `unpolished` → `analog-warm` |
| `polished` | `pristine` → `radio-ready` → `crystal clear` → `hi-fi` |
| `dark` | `brooding` → `menacing` → `ominous` → `shadowy` |
| `nostalgic` | `wistful` → `bittersweet` → `vintage` → `reminiscent` |
| `intimate` | `close-mic'd` → `whispered` → `bedroom` → `confessional` |

Same intent, different cache hits. Often unblocks stuck regenerations.

## v5.5-specific empirical findings (post-March 2026)

These are tips discovered AFTER v5.5 release, validated through multi-user community testing. Several CONTRADICT earlier-era advice — flagged where applicable.

### v5.5 = personalization layer over v5 audio engine

v5.5 is NOT a new audio model; it's v5's audio engine + Voices/Custom Models/My Taste personalization layers stacked on top.

Practical implication: **detailed prompts override My Taste**; vague prompts let it dominate. If output feels repetitive across sessions, prompt more verbosely to neutralize My Taste's silent biasing.

### Voice Audio Influence: raise it when resemblance is poor

**First-party direction, narrowly scoped:** Suno's Voices walkthrough says to set Audio Influence "fairly high," and its Voices FAQ says to experiment with turning it up, when fixing poor voice resemblance. **Neither publishes a number**, so every specific threshold below is community-derived and unverified — not officially confirmed.

Community reports describe higher slider values importing recording artifacts (mic coloration, room tone, breath placement) along with vocal identity. Treat that as a reported tradeoff: raise the slider when resemblance is poor, compare outputs, and back down if artifacts intrude — then improve the source recording rather than chasing a threshold Suno has not published.

Full detail in [voices.md](voices.md#audio-influence-with-an-active-voice).

### Voice clone training: single 90-120s clip with variety

**Single clip with intentional dynamic variety beats multiple flat-dynamic clips.** Suno's auto-windowing picks the most-frequent dynamic from training material; a single varied clip exposes your full range to the picker.

### Delivery tags are now per-section local in v5.5

`[Whispered]`, `[Belted]`, `[Falsetto]`, `[Humming]`, `[Scream]`, `[Ad-lib]`, `[Call and Response]` reshape the cloned voice WITHIN the section they appear in — they no longer apply globally.

This enables **single-voice album-arc dynamics**: same Voice clone, different delivery character per song or per section, just by adding the right delivery tag inside the section.

### Custom Model break-in period

First 5-10 generations from a freshly-trained Custom Model feel generic. Quality "activates" after 5-10 exposures — Suno calibrates the model's response to your usage patterns over the first batch.

**Don't judge a Custom Model's quality on first 3 generations.** Burn through 10 before evaluating.

### My Taste creative flattening (community debate)

Community blind tests found disabled-MyTaste batches show MORE instrumentation/tonal variety than enabled-MyTaste batches. Effect is real but bounded — **detailed verbose prompting neutralizes the flattening**.

Advanced creators with verbose prompting see no difference. Casual users with terse prompts get flattened toward their voting history.

For maximum diversity: prompt verbosely OR temporarily disable My Taste in settings (if exposed).

### Replace Section is the v5.5 economy workflow

The cost-effective workflow shifted from "regenerate the whole song until perfect" to:

1. Generate full song
2. Identify the single weakest section
3. **Replace Section** that section 3-5 times
4. Composite the best take

Cheaper credits, better outputs, less wheel-spinning. New default.

### v4.5 × v5.5 Cover hybrid

Generate creatively in v4.5 Plus first → then `Cover Song` → v5.5 with style field nearly empty + Audio Influence ~30% (community-derived; not officially confirmed).

**Why this works:** v4.5 has more creative variety on initial generation; v5.5 has cleaner voice quality. Hybrid extracts strengths of both.

### Persona extraction from existing songs

Three-dot menu on any song → `Create` → `Make Persona` → select 30s vocal window.

Enables **album-vocal continuity across genre-diverse tracks** — same vocal character on a synth-pop song and an acoustic ballad and a hip-hop track.

### Studio "Remove Effects" per-stem (v5.5)

In Suno Studio with Auto Split stems: right-click an individual stem → `Remove Effects`. Strips processing from JUST that stem (e.g., strip reverb from vocals only) before DAW export.

Cleaner external mixing; you keep the production on stems you like and dry the ones you'll re-process.

### Manual BPM lock for tempo drift

If a generated track has subtle tempo drift, in Studio: Transport Bar → tempo display → `Manual BPM`. Suno performs a Time-Stretch Audit, then stems snap cleanly to your DAW grid without warping artifacts.

### 3.4K sibilance characteristic

v5.5 outputs frequently have sibilance buildup around 3.4kHz. **Aggressive de-essing post-export is often required** for vocal-clarity-critical work.

Some creators retain v4.5 Plus access for vocal-critical work and use v5.5 for instrumental-critical work — picking the model based on whether the vocal needs to sit clean.

### Legacy Editor for Extend (workaround)

The new Editor's Extend function often produces glitchy output in v5.5. Workaround: switch to Legacy Editor via the `...` menu, run Extend there, get reliable output.

Suno is aware; treat as known issue until fixed.

## Confidence note

Community-validated through extensive empirical testing across multiple users on hookgenius, blakecrosley, jackrighteous, songaifarm guides + Reddit r/SunoAI consensus + creator-community testing. Suno does not officially document most. Effects reproducible; exact magnitudes (e.g., "20% higher adherence") are folk wisdom, not measured.

Treat as **MEDIUM-HIGH confidence empirical patterns** — solid enough for production prompts, but always A/B test against straight-formula approach when stakes are high.

**Conflicts / unverified:**

- **My Taste override behavior:** Suno docs say it never overrides explicit prompts; community reports show it can lock cycles requiring temporary disable to escape. Unresolved.
- **Voice cloning consistency across mics/environments:** known unstable; root cause undocumented.
- **Audio Influence behavior split** between voice-clone context vs audio-reference context: community-reported as different (community-derived 25-30% sweet spot for voice clone; community-derived 60-80% sweet spot for audio-reference upload), but the behavior split and exact thresholds are not officially confirmed.
