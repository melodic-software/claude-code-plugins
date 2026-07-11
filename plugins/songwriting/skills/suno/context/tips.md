# Community-validated tips & workflow

Techniques here are **MEDIUM confidence** — multi-source consensus across community guides, YouTube tutorials, Reddit threads, but **NOT officially documented by Suno**. Effects are real (everyone agrees they work); exact magnitudes are folk wisdom.

Surface as **opt-in suggestions**, not commands. Default to HIGH-confidence techniques in `style.md` and `lyrics.md`.

## Performance shaping (in lyrics)

### Capitalization for vocal pressure

**Effect:** ALL-CAPS turning-point words trigger vocal grit, pressure, intensity spike.

**Use:** strategically on 1-2 words per section, never throughout.

```
The walls are closing in
PRESSURE IS RISING
And I can't breathe anymore
```

**Don't:** ALL-CAPS the entire chorus — effect dilutes to no effect.

### Vowel stretching for melisma

**Effect:** Multiple repeated vowels force sustained / melismatic delivery.

**Use:** 3-5 extra vowels = natural sustain. 20+ glitches into digital artifacts.

```
I love yoooou (4 extra o's)     ← natural melisma
I love yoooooooooooou (12+)      ← glitchy
```

Best on **emotional peak words** in a chorus.

### Ellipsis for breath / pause

**Effect:** `...` produces a natural 0.5-2 second pause.

```
And then... I realized
The world was... different now
```

Reliable, low-risk. HIGH confidence among community sources.

### Hyphenation for staccato

**Effect:** Hyphens between letters force letter-by-letter staccato delivery.

**Use:** rap emphasis, EDM build-ups, single-word punches.

```
L-i-v-e the moment
W-a-t-c-h me now
```

Don't overuse — works as accent, fails as a default.

### Parenthetical cues for inline directives

**Effect:** Short cues in `()` are interpreted as performance directives, not sung lyrics. Long cues (4+ words) get sung.

**Use:** 1-3 word performance hints inline.

```
In the shadows (whispered)
The crowd is cheering (echoes)
She's looking at me (softly)
Building, building (building)
```

Reliable. HIGH confidence — close to documented behavior.

### Line breaks for melodic separation

**Effect:** Each line ending forces a melodic boundary. Phrases on one line run together.

**Use:** one idea per line, especially in verses.

```
Bad:  I walked the streets last night and saw a stranger looking at me

Good: I walked the streets last night
      And saw a stranger
      Looking at me
```

### Manual repetition (vs `(x2)` notation)

**Effect:** `(x2)` after a line is largely ignored. Writing the line twice produces actual repetition.

```
Bad:   Take me higher (x2)

Good:  Take me higher
       Take me higher, oh

Best:  Take me higher
       (Take me higher)
       Higher than I've ever been
```

Small variation in the second line (parenthetical, ad-lib, descriptor) sounds more natural than literal duplication.

### Inline backing vocals / FX

**Effect:** Square-bracketed inline cues add layered backing or effects.

```
I love you [ahhs rising]
She's gone [reverb tail]
Take it back [crowd noise]
```

MEDIUM confidence — works on 5/10 generations. Worth trying, regenerate if missed.

### Timing cues

**Effect:** `[at 0:15 vocals enter]`-style cues nudge timing. Adherence ~70%.

**Use:** for atmospheric intros / outros, not load-bearing.

LOW-MEDIUM confidence. Use structural tags (`[Intro]`, `[Outro]`) as primary control; timing cues as secondary nudge.

## Style-prompt micro-tricks

### Front-load the highest-priority tag

Order matters. Whatever you put first carries most weight. Genre first; mood second; everything else after.

### Use sound descriptors instead of artist names

Artist names are filtered or ignored. Use the sound:

| Want | Use instead |
|------|-------------|
| "like Drake" | `Toronto trap bounce, melancholic melodic flow` |
| "like Billie Eilish" | `whispered female vocals, dark bedroom-pop, sub-bass, sparse production` |
| "like Daft Punk" | `French house, vocoder vocals, filter-house chord stabs, side-chained pump` |
| "like Adele" | `belted female vocals, soulful piano ballad, rich room reverb` |
| "like Skrillex" | `aggressive dubstep, growly wobble bass, vocal chops, half-time drop` |

### Anchor BPM with groove

`128 BPM, four-on-the-floor` reinforces tempo more than `128 BPM` alone. Adherence climbs.

### "Polished radio-ready" vs "lo-fi bedroom"

Two macro-descriptors that cover the production layer for ~80% of pop / rock prompts:

- `polished radio-ready production` — clean, compressed, modern, balanced
- `lo-fi bedroom production` — warm, intimate, slightly muddy, low-budget feel

## Iterative workflow tips

### 1. Generate 4 versions per prompt

Variance is high. First generation is rarely best — A/B compare across 4 to find the keeper.

### 2. A/B test one variable at a time

Don't change three things at once. Change mood OR instrumentation OR BPM, regenerate, compare. Document what helped.

### 3. Stem-first workflow for production

Generate full track → export 12-track stems → polish in Logic / Ableton / Pro Tools. Suno is great at the rough mix; external DAW is great at the final 10%.

### 4. Persona library for cross-project consistency

Save favorite vibe templates as Personas. When you find a Voice + style combo that works, "Make Persona" and reuse across the next 5-10 songs to maintain coherent project sound.

### 5. My Taste training

Vote thumbs up / down on early generations. After 50-100 votes, default model behavior shifts toward your preferences. Free tier — costs nothing.

### 6. Custom Model curation (Pro / Premier)

Train Custom Models only on tracks YOU own AND that share a coherent sound. Mixing a synth-pop track and a metal track in the same training set gives you a confused average.

### 7. Replace Section over full regeneration

If verse 2 is the only weak section, use Replace Section (Pro / Premier). Keeps the rest. Cheaper than generating 8 full songs hoping one has both verse 1 and verse 2 right.

### 8. Extend strategically with structural tags

When extending: put `[Bridge]`, `[Outro]`, `[Final Chorus]` in the new lyrics field. Suno reads the structural tag and shapes the extension to match.

### 9. Reuse exact metadata for sequels

For a sequel-sounding follow-up: reuse exact mood + key + BPM + production tags. Change only topic/lyrics.

### 10. Voice cloning prep

Best clone results from:

- 3 acapella clips
- Each 30-90 seconds
- Across emotional range (gentle / mid / intense)
- Same mic, same room, same distance
- Clean room (treated or quiet)

## When to stop iterating

If after 5 regenerations and 3 variable changes the output still misses, the underlying genre/mood/instrumentation triangle may be inconsistent. Examples:

- "country trap with classical violin" — pick ONE direction
- "aggressive lullaby" — pick energetic OR soft
- "ambient drum'n'bass" — pick still OR fast

Rebuild the prompt from the 6-layer formula. Sometimes the issue isn't the prompt's wording — the user is asking for something incoherent.
