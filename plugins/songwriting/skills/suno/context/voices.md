# Voices — full guide

Voices clones YOUR singing identity. v5.5 only. **Pro / Premier tier.** 18+, geographically gated.

## What Voices does

- Captures vocal timbre, register, breathiness, accent characteristics from your acapella recording
- Applies that voice to any generated song where you select it
- Account-locked: only you can create with your voice profile (privacy + anti-impersonation)
- Layers cleanly with Custom Models (your sound × your voice)

## Recording requirements

| Spec | Detail |
|------|--------|
| Length per clip | 15 sec minimum, 4 min maximum |
| Auto-selection | System picks the best 2-min segment |
| Preferred input | Acapella (no music underneath) |
| Music underneath OK? | Yes — auto-isolated via stem split, but quality drops |
| Mic | Decent mic essential (USB condenser or better) |
| Room | Acoustically neutral; no echoey bathroom takes |
| Model gate | Must select v5.5 in Custom mode |

## Best-practice recording session

**Single 90-120 second clip with intentional vocal variety** (per community empirical testing). Tonal and emotional variety within ONE clip produces stronger clones than multiple separate flat-dynamic clips.

Record one continuous 90-120s acapella performance covering:

1. **Gentle / quiet section (~30s)** — soft, intimate, conversational
2. **Mid-dynamic section (~30s)** — standard performance, melodic line
3. **Intense / belted section (~30s)** — powerful, emotional peak

Same mic, same room, same distance across the whole clip. Record dry — no reverb, no compression, no autotune. Suno applies effects later in generation.

Sing actual melodies, not spoken word. The model learns your sung timbre, not your speaking voice.

**Why single clip + variety beats multiple flat clips:** Suno's auto-selection picks a 2-min window from training material. A varied single window gives it the full dynamic spectrum to model from; multiple flat clips often get sampled at the most-frequent dynamic and miss your range.

## Verification phrase

Anti-impersonation guard. After upload:

1. Suno displays a random phrase on screen
2. You read the phrase aloud (recorded live)
3. System compares the spoken phrase against your uploaded singing
4. Match → voice approved

This blocks: cloning a public figure's voice from YouTube, cloning a friend / collaborator without consent. The verification recording proves the same person produced both samples.

## Activating a Voice in generation

1. Custom mode (required — Voices not available in Simple)
2. Voice selector dropdown → pick your voice
3. **Set Audio Influence slider to 25-30%** (sweet spot per community empirical testing — see below)
4. Climb in 10% increments only if voice identity is too weak

### Audio Influence sweet spot (HIGH confidence, contradicts initial Suno docs)

**Empirical sweet spot is 25-30%, NOT the higher values some early Suno docs suggested.**

| Slider | Effect |
|--------|--------|
| 25-30% | Sweet spot — voice identity preserved, recording artifacts minimized |
| 40-50% | Voice still identifiable, room tone / mic artifacts start surfacing |
| 60-80% | Voice character preserved BUT imports recording artifacts, breath sounds, room reverb from training clips |
| 85%+ | Voice clone over-fits to training audio's environment (mic, room), output sounds like the recording session, not a produced track |

**Why this matters:** higher slider values cause Suno to inherit the **physical environment** of your training recording (mic coloration, room tone, breath placement) as much as the voice itself. 25-30% extracts vocal identity while letting the song's production layer apply normally.

Start low, climb only if needed. Most users settle at 25-30%.

### Voice clone input — quality over quantity

**90 seconds to 2 minutes total, with intentional vocal variety.** Pure repetition of one phrase or one emotional register produces a WEAKER clone than the same total length covering varied dynamics.

Best results from a single 90-120s clip containing:

- A gentle / quiet section (~30s)
- A mid-dynamic conversational section (~30s)
- An intense / belted section (~30s)

Same mic, same room, same distance. Sing actual melodies, not spoken word.

## Critical rule: drop conflicting descriptors

When a Voice is active, style prompt's vocal descriptors **conflict** with the cloned identity.

**Drop these from the style prompt:**

- Gender markers (`female vocals`, `male vocalist`, `androgynous`)
- Tone descriptors (`raspy`, `breathy`, `airy`, `nasal`)
- Register descriptors (`falsetto`, `chest voice`, `belted` — unless the Voice was trained on belted material)

**Keep these:**

- Style/genre tags (genre, mood, instrumentation, BPM, production)
- Section tags in lyrics (`[Verse]`, `[Chorus]`, etc.)
- Performance directives in lyrics parentheticals (`(whispered)`, `(softly)`) — these tell the cloned voice HOW to deliver, not what to BE

Example style prompt with active Voice:

```
indie folk, fingerpicked acoustic guitar, warm upright bass,
sparse brushed drums, 94 BPM, key of D minor,
no reverb wash, no synths, vintage tube warmth
```

Notice: zero vocal descriptors. The Voice handles vocal identity entirely.

## Multi-voice workflows

For duets / call-and-response across two cloned voices:

1. Both collaborators must each have their own Voice trained
2. Each generates a section using THEIR voice
3. Studio comps parts onto separate tracks
4. Export as one mix

Suno doesn't support "select voice A for verse 1 and voice B for verse 2" in a single generation — work around with Studio multitrack assembly.

## Reporting / misuse

In-app report flow for misused voices. If someone clones your voice without consent (despite verification — edge case), report → Suno reviews → voice profile takedown.

## What's NOT documented

These edge cases aren't surfaced in current help articles — verify if you hit them:

- Max voices per account
- Voice retraining / editing flow (re-upload to refine?)
- Voice deletion procedure
- Whether voices transfer across subscription downgrades
- Whether Voices integrates with Persona system

If any matter for your workflow, contact Suno support directly.

## Sources

`help.suno.com/articles/11362369` (Voices: Use Your Voice in Suno), `help.suno.com/articles/11362433` (Voices FAQ), `help.suno.com/categories/2327233-v-5-5-voices-custom-models-my-taste`.
