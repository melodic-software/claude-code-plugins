# What's new in v5.5

**Released March 26, 2026** (verified 2026-07-18 against <https://suno.com/blog/v5-5>; still the current model). v5.5 is a personalization-focused upgrade over v5 (Sep 2025). Core prompt syntax unchanged from v5; what changed is **adherence quality** plus three new identity layers.

## Three new layers

### 1. Voices (clone your singing identity)

**Pro / Premier only.** Clone your own vocals so generated songs sound like YOU singing.

| Detail | Spec |
|--------|------|
| Audio sources | Existing Suno songs, microphone recording, uploaded file |
| Length per clip | 15 seconds minimum, 4 minutes maximum |
| Auto-selection | System picks the best 2-minute window |
| Preferred input | Acapella recordings (no music underneath) |
| Stem extraction | Applied automatically if file contains music |
| Verification | Speak a random phrase — proves voice ownership |
| Privacy | Private by default, account-locked, non-shareable |
| Activation | Select voice from dropdown in Custom mode + raise Audio Influence |

Clip length, 2-minute auto-selection, verification, and privacy rows verified 2026-07-18 against <https://help.suno.com/en/articles/11362369>; Pro/Premier tier per <https://suno.com/blog/v5-5>.

**Critical prompting rule when a Voice is active:**

> **Drop gender/tone descriptors from the style prompt.** They conflict with the cloned voice and degrade output quality.

For best clone quality: record 3 acapella clips across emotional range (gentle, mid, intense) in a quiet room. Use the same mic across clips.

### 2. Custom Models (fine-tune on your catalog)

**Pro / Premier only.** Train a personal v5.5 model on your own original tracks.

| Detail | Spec |
|--------|------|
| Min input | 6+ owned original tracks |
| Max models | 3 per account |
| Bulk upload | Supported |
| Training time | 2-5 minutes |
| Result | Fine-tuned v5.5 reflecting YOUR production patterns, instrumentation, harmonic preferences |
| Privacy | Private, non-shareable |

Partially verified 2026-07-18: max-3-models and Pro/Premier rows confirmed against <https://help.suno.com/en/articles/11362305>; min-tracks and training-time figures are not in official docs — treat as unverified.

**Key behavior:** style tags now operate **relative to your baseline**, not generic averages. If your catalog is heavy on lo-fi tape saturation, "polished mix" might still come out warmer than generic Suno polished mix.

**Best practice:** **train separate models for separate sounds.** Don't mix genres in one training set — model averages across them and loses the per-style signal.

**Break-in period (community-validated empirical):** first 5-10 generations from a freshly-trained Custom Model feel generic. Quality "activates" after 5-10 exposures as Suno calibrates the model's response. **Don't judge model quality on first 3 generations** — burn through 10 before evaluating.

### 3. My Taste (passive preference learning)

**All tiers, including free.** Suno tracks your thumbs up/down votes and which songs you keep, then biases default model behavior toward your preferences.

- No explicit action needed beyond normal voting
- Powers the **Magic Wand** style suggestions
- Effect builds over time — early sessions feel generic; after 50-100 votes the bias is noticeable
- **Override:** explicit detailed prompts override My Taste preferences. If you want a specific output, prompt explicitly; My Taste is the silent default-shifter

**Creative flattening debate (MEDIUM confidence):** community blind tests show disabled-MyTaste batches produce more instrumentation/tonal variety than enabled-MyTaste batches. Effect is bounded — verbose detailed prompting neutralizes it. Casual users with terse prompts get flattened toward voting history. For diversity: prompt verbosely OR temporarily disable My Taste in settings (if exposed in your tier).

## v5.5 vs v5 vs v4 — deltas at a glance

| Feature | v4 | v5 (Sep 2025) | v5.5 (Mar 2026) |
|---------|----|----|------|
| Style prompt limit | ~200 chars | ~1,000 chars | ~1,000 chars |
| Lyrics limit | 3,000 chars | 5,000 chars (quality sweet spot ~3,000) | 5,000 chars (quality sweet spot ~3,000) |
| Numeric BPM accuracy | ~70% | ~85% | ~90% |
| Adherence to nuanced descriptors | low | medium | high |
| Voices | — | — | ✓ |
| Custom Models | — | — | ✓ |
| My Taste | — | — | ✓ |
| Tag syntax | basic | full | full |
| Multilingual | limited | ~50 langs | ~50 langs |

Char-limit rows verified 2026-07-18 against third-party testers ([hookgenius character limits](https://hookgenius.app/learn/suno-character-limits/), [aimusicapi cheat sheet, 2026-07-03](https://aimusicapi.ai/en/blog/suno-ai-prompt-character-limits)) — no official Suno page states field limits. Other rows unverified community figures.

**This skill targets v5.5 only.** Legacy v4 prompting (200-char era, fewer tags) is out of scope.

## Multilingual

- ~50 languages supported with varying quality
- **Best**: English, Spanish, Portuguese, French, German, Italian, Japanese, Korean, Mandarin, Russian, Arabic
- **Auto-detected** from lyrics text — no explicit language specification needed
- Optional reinforcement: name the language in style prompt (`Spanish flamenco`, `Mandarin pop ballad`)
- Language tags (`[Spanish]`, `[Spanglish]`) work as **soft hints** but aren't reliable controllers — write in target language for actual control
- Section tags (`[Verse]`, `[Chorus]`) are language-agnostic
- Pronunciation, rhyme, and cultural phrasing are strongest in major languages; folk styles in low-resource languages may falter

## Subscription tier matrix

| Feature | Free | Pro | Premier |
|---------|------|-----|---------|
| Custom mode | ✓ | ✓ | ✓ |
| My Taste | ✓ | ✓ | ✓ |
| Personas | ✓ | ✓ | ✓ |
| Cover | ✓ | ✓ | ✓ |
| Extend | ✓ | ✓ | ✓ |
| Audio upload | 60s | 120s | 120s |
| 2-track stems | ✓ | ✓ | ✓ |
| 12-track stems | — | ✓ | ✓ |
| Voices | — | ✓ | ✓ |
| Custom Models (up to 3) | — | ✓ | ✓ |
| Replace Section | — | ✓ | ✓ |
| Suno Studio | — | — | ✓ |

(Verify against current Suno pricing page — tier feature lists drift.)

- Studio row corrected 2026-07-18: **Premier-exclusive** per <https://suno.com/pricing> — Pro has no Studio access.
- Audio-upload row conflicts with the 8-minute Pro/Premier figure stated elsewhere in this skill — unresolved; re-verify before relying on either.
- Free-tier generation runs on **v4.5-all**, not v5.5 (third-party report: TechRadar).

## Sources

Primary: `help.suno.com/en/articles/11362305` (v5.5 release), `help.suno.com/en/articles/11362369` (Voices), `help.suno.com/en/articles/11362497` (Custom Models), `suno.com/blog/v5-5`.
