# What's new in v5.5

**Released March 26, 2026** (verified 2026-07-18 against <https://suno.com/blog/v5-5>; still the current model). v5.5 is a personalization-focused upgrade over v5 (Sep 2025). Core prompt syntax unchanged from v5; what changed is **adherence quality** plus three new identity layers.

**Post-baseline addition, 2026-08-12.** The 2026-07-18 verification stamp above predates the **Duration slider**, which Suno's release notes announced on Jul 20 2026 for Web on the V5.5 model — two days after that pass. It is not a March-launch layer and is deliberately **absent from the version-delta table below**, which tracks model capabilities rather than Create-form controls; a row there would misdate it to March. Documented in [advanced.md](advanced.md#duration-slider-create-form).

## Three new layers

### 1. Voices (clone your singing identity)

**Pro / Premier. Free plans got a *trial* on Aug 7 2026 — with an unresolved platform caveat (see below).** Clone your own vocals so generated songs sound like YOU singing.

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

Clip length, 2-minute auto-selection, verification, and privacy rows verified 2026-07-18 against <https://help.suno.com/en/articles/11362369>.

**Tier corrected 2026-08-08.** The March 2026 Pro/Premier gate (per <https://suno.com/blog/v5-5>) has been superseded. <https://suno.com/release-notes>, Aug 7 2026: "We brought Voices to both iOS and Android. Record your voice once and use it on any song. Now available to try on free plans."

**Unresolved platform caveat — do not assume free Voices on web.** That release-note entry is tagged *Improvement, iOS, Android, Create* with **no `Web` tag**, while every other web-touching entry in the same window carries one. <https://suno.com/pricing> shows no Voices bullet under Free, and both Voices help articles are silent on plan gating. Free-plan Voices may therefore be mobile-only. Unresolved as of 2026-08-08 — verify in-app before relying on it.

**Critical prompting rule when a Voice is active:**

> **Drop gender/tone descriptors from the style prompt.** They conflict with the cloned voice and degrade output quality.

**MEDIUM confidence — community-derived; Suno does not publish a recommendation for clip count or target length.** For best clone quality, record one continuous 90-120s acapella clip in a quiet or treated room, using the same mic and consistent distance throughout. Include gentle, mid-dynamic, and intense / belted passages within that single clip so it covers your emotional range. This recommendation sits within Suno's published 15-second-to-4-minute input limit and 2-minute auto-selection behavior above.

An earlier revision advised three separate clips; that guidance was deliberately retired in favor of the single varied clip, the only approach here with a stated mechanism: community reports say Suno's auto-selection favors the most-frequent dynamic, so variety within one clip beats several flat-dynamic clips.

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
- **Best**: English, Spanish, Portuguese, French, Japanese, Korean, Mandarin — these seven are the sourceable set. German, Italian, Russian and Arabic are also commonly listed here but are **unsourced**: no source was found placing them in the top tier, and none was found placing them outside it either. Retained, unverified.
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
| Audio upload | up to 8 min | up to 30 min | up to 30 min |
| Stem separation — Split from Mix (2 stems) | — | ✓ | ✓ |
| Stem separation — Auto Split (up to 12 stems) | — | ✓ | ✓ |
| Stem separation — Advanced Split (~100 instruments) | — | — | ✓ |
| Voices | trial only (see caveat above) | ✓ | ✓ |
| Custom Models (up to 3) | — | ✓ | ✓ |
| Replace Section | — | ✓ | ✓ |
| Suno Studio | — | — | ✓ |

(Verify against current Suno pricing page — tier feature lists drift.)

- Studio row corrected 2026-07-18: **Premier-exclusive** per <https://suno.com/pricing> — Pro has no Studio access.
- Audio-upload row verified 2026-07-18 against <https://suno.com/pricing>: Free up to 8 minutes, Pro/Premier up to 30 minutes (the earlier 60s/120s figures were stale).
- **Stem rows corrected 2026-08-08** against <https://suno.com/pricing>. Free reads "No stem separation" — the previous "2-track stems: Free ✓" row was false. Pro carries "2 stem separation types (Auto; Split from mix)"; Premier carries "3 stem separation types (… and Advanced split)". Naming correction too: Auto Split / Split from Mix / Advanced Split are three **modes**, not track counts — "12-track stems" was a misnomer for Auto Split, which yields up to 12 stems.
- Free-tier generation runs on **v4.5-all**, not v5.5 (third-party report: TechRadar).

## Sources

Primary: `help.suno.com/en/articles/11362305` (v5.5 release), `help.suno.com/en/articles/11362369` (Voices), `help.suno.com/en/articles/11362497` (Custom Models), `suno.com/blog/v5-5`.
