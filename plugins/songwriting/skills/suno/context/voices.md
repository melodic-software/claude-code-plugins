# Voices — full guide

Voices clones YOUR singing identity. v5.5 only. 18+, geographically gated.

**Tier updated 2026-08-08 — Pro / Premier, plus a free-plan TRIAL.** The release note says free plans can "try" Voices; **a trial is not all-tier entitlement, and this file must not describe it as one.** <https://suno.com/release-notes>, Aug 7 2026: "We brought Voices to both iOS and Android. Record your voice once and use it on any song. Now available to try on free plans." **Caveat:** that entry carries no `Web` tag (unlike other web-touching entries in the same window), `suno.com/pricing` lists no Voices bullet under Free, and both Voices help articles are silent on plan gating — so free-plan Voices may be mobile-only. Unresolved; verify in-app.

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

Clip length, 2-minute auto-selection, and acapella-preferred rows verified 2026-07-18 against <https://help.suno.com/en/articles/11362369> (which also confirms the 18+ and geographic restrictions above); mic/room/model-gate rows are community best practice.

## Best-practice recording session

**Single 90-120 second clip with intentional vocal variety** (per community empirical testing). Tonal and emotional variety within ONE clip produces stronger clones than multiple separate flat-dynamic clips.

Record one continuous 90-120s acapella performance covering:

1. **Gentle / quiet section (~30s)** — soft, intimate, conversational
2. **Mid-dynamic section (~30s)** — standard performance, melodic line
3. **Intense / belted section (~30s)** — powerful, emotional peak

Same mic, same room, same distance across the whole clip. Record dry — no reverb, no compression, no autotune. Suno applies effects later in generation.

Sing actual melodies, not spoken word. The model learns your sung timbre, not your speaking voice.

**Why single clip + variety beats multiple flat clips:** Suno's auto-selection picks a 2-min window from training material. A varied single window gives it the full dynamic spectrum to model from; multiple flat clips often get sampled at the most-frequent dynamic and miss your range.

### Two-stage bootstrap for non-singers

**LOW-MEDIUM confidence — a SINGLE community post plus its comment thread, not multi-source consensus.** Read 2026-08-11 from [r/SunoAI, "Another useful trick to use your own voice in Suno, even if you cannot sing well"](https://www.reddit.com/r/SunoAI/comments/1ujzbqj/another_useful_trick_to_use_your_own_voice_in/) (posted 2026-06-30, 152 votes, 58 comments). Not documented by Suno. Untested here.

For a writer who cannot deliver the sung 90-120s session above, the reported route is to clone twice:

1. Record **30-60s of ordinary speech** — read anything, no singing — clean and dry, exported as WAV.
2. Save it as a voice, then generate a short a cappella test using it as the lead voice, with a style prompt asking for unaccompanied vocal and clipped, on-beat delivery.
3. Reported slider settings for that test generation: **Weirdness 0%, Style Influence 100%, Audio Influence ~95-100%.**
4. From the generated take, **create a second voice from the part where the voice actually sings** — that second voice is the one to use.

**This does not contradict "sing actual melodies, not spoken word" above — it agrees with it.** The speech clip is scaffolding only; the voice a writer actually keeps is still built from sung material. What the technique changes is where the sung material comes from.

**Reported failure mode:** the stage-2 test generation usually arrives with a beat or backing behind the vocal — the poster reports the voice-creation step filters to the vocal anyway, and that selecting only the cleanest sung span works better.

**One commenter reports the "make this voice public" toggle is ON by default when creating a voice.** Unverified against Suno's own documentation, and the same thread disputes it. Check the toggle yourself before finishing a voice rather than trusting either claim.

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
3. If voice resemblance is poor, **raise the Audio Influence slider**
4. Increase gradually while checking whether resemblance improves

### Audio Influence with an active Voice

**First-party direction, narrowly scoped:** Suno's Voices walkthrough says to set Audio Influence "fairly high," and its Voices FAQ says to experiment with turning it up, when fixing poor voice resemblance. Neither article publishes a number or claims that higher settings are universally better.

Specific thresholds — including the `>=70%` starting point in the troubleshooting guide — are **community-derived and unverified**, not first-party guidance.

Community reports also describe higher settings carrying more of the source recording's artifacts. The ranges below are retained as **unverified community observations**, not documented slider behavior:

| Slider | Effect |
|--------|--------|
| 40-50% | Voice still identifiable, room tone / mic artifacts start surfacing |
| 60-80% | Voice character preserved BUT imports recording artifacts, breath sounds, room reverb from training clips |
| 85%+ | Voice clone over-fits to training audio's environment (mic, room), output sounds like the recording session, not a produced track |

Raise Audio Influence when resemblance is poor. If artifacts increase, treat that as a community-reported tradeoff: compare outputs, back down as needed, and improve the source recording rather than relying on an official threshold that Suno has not published.

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

`help.suno.com/en/articles/11362369` (Voices: Use Your Voice in Suno), `help.suno.com/en/articles/11362433` (Voices FAQ), `help.suno.com/en/categories/2327233-v-5-5-voices-custom-models-my-taste`.
