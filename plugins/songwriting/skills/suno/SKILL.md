---
name: suno
description: "Generate and refine Suno AI music prompts (v5.5) — style prompts, tagged lyrics, genre templates, troubleshooting, tips, features, and genre research via an action router. Use when: 'suno prompt', 'write suno lyrics', 'style prompt for suno', 'BPM prompting', 'vocal tags', 'fix garbled lyrics', 'voice cloning suno', 'suno genre', 'suno studio', or any Suno prompt-craft request."
argument-hint: "[action] [args] (e.g., /suno prompt, /suno lyrics, /suno genre <name>) — full action list in body; default: menu"
user-invocable: true
disable-model-invocation: false
---

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Suno is an AI music platform; the prompt is the instrument. This skill helps the user **generate, refine, and debug Suno prompts** — both the **style/genre** and **lyrics** fields — using v5.5-era best practices, the documented tag taxonomy, and community-validated performance tricks.

The skill is a **prompt-craft assistant**, not an audio generator. Suno produces audio; this skill makes sure the prompt going INTO Suno is sharp, on-format, free of common pitfalls.

Suno v5.5 (released March 26, 2026; verified 2026-07-18 against <https://suno.com/blog/v5-5>) preserved v5's prompt syntax but improved adherence to nuanced descriptors and added three personalization layers (Voices, Custom Models, My Taste). Everything below targets v5.5 unless noted; legacy v4 (~200-char style prompt) is out of scope.

## Action Router

Parse `$ARGUMENTS`: first token = action, remainder = args. If empty
(e.g. model-invoked from a natural-language request), infer the action
from conversation context; show this menu only when no actionable
context exists.

| Action | Purpose | Detail |
|--------|---------|--------|
| `prompt <intent>` | Build a complete style prompt + lyrics from a song idea | inline + [context/style.md](context/style.md) + [context/lyrics.md](context/lyrics.md) |
| `lyrics <intent>` | Generate or refine lyrics with section tags, vocal tags, **per-section style overrides**, performance cues | [context/lyrics.md](context/lyrics.md) |
| `style <intent>` | Generate a style prompt using the 6-layer formula | [context/style.md](context/style.md) |
| `clean <text>` | Review user's existing prompt, flag pitfalls, propose rewrite | [context/troubleshoot.md](context/troubleshoot.md) + [context/style.md](context/style.md) |
| `research <topic>` | **On-the-fly external research** — artist sonic profiles, current trends, niche genres, specific reference songs (BPM/key/instrumentation). Translates findings into Suno descriptors. | [context/research-recipes.md](context/research-recipes.md) |
| `tags` | Show the full tag taxonomy (structural, vocal, instrument, mood, ending) | [context/lyrics.md](context/lyrics.md) |
| `genre <name>` | Genre handler — 4 modes: load template (12 built-ins), research a niche genre, suggest genres for a vibe, or show a genre family tree | [templates/<name>.md](templates/) + [context/genre-taxonomy.md](context/genre-taxonomy.md) |
| `troubleshoot <symptom>` | Diagnose a specific failure (hallucinated lyrics, BPM ignored, vocal artifacts, exclusions failing) | [context/troubleshoot.md](context/troubleshoot.md) |
| `tips` | Community-validated lyric-side performance tricks (caps, vowel stretch, ellipses, parentheticals) — MEDIUM confidence | [context/tips.md](context/tips.md) |
| `power-tips` | Empirically-validated power-user techniques (tag weighting, genre fusion order, stem-loop refinement, two-pass vocal isolation, persona-as-draft, punctuation cadence, describe-this-song, Custom Model tricks) — MEDIUM-HIGH confidence | [context/power-tips.md](context/power-tips.md) |
| `features` | v5.5 feature index — Voices, Custom Models, Personas, Cover, Extend, Replace, Stems, Studio, Sliders | [context/v55-features.md](context/v55-features.md) + [context/advanced.md](context/advanced.md) |
| `voices` | Voice cloning deep dive — recording, verification, conflict rules with style prompt | [context/voices.md](context/voices.md) |
| `studio` | Suno Studio (GAW) — what's possible, clip ops, Take Lanes, Warp Markers, MIDI, stems | [context/studio.md](context/studio.md) |
| `workflow <recipe>` | Demo upload, edit/rearrange, add instruments, vocal comping, multi-genre cover chain — 8 recipes | [context/workflow-recipes.md](context/workflow-recipes.md) |

If the action is unknown, show this table and ask what the user wants.

---

## Load-bearing fundamentals (inline — every action assumes these)

### The 6-layer formula (style prompt ordering)

Order matters — early tags carry more weight. Front-load genre.

1. **Genre / subgenre** — specific, not "pop" → `synth-pop, 80s-inspired`
2. **Mood** — 2-3 words → `nostalgic, hopeful` (not 9 conflicting moods)
3. **Instrumentation** — specific → `fingerpicked acoustic guitar` (not just "guitar")
4. **Vocal direction** — acoustic descriptors → `breathy, intimate, slight rasp` (not "amazing")
5. **BPM** — numeric → `128 BPM` (not "fast")
6. **Production** — `polished mix`, `lo-fi tape hiss`, `compressed and aggressive`

Sweet spot: **5–8 distinct tags**. Fewer than 4 → generic. More than 10 → conflicting signals.

### Character budgets

| Field | Limit | Notes |
|-------|-------|-------|
| Style prompt (v5/v5.5) | **~1,000 chars** | Up from ~200 in v4. Truncates silently. Front-load critical content. |
| Lyrics | **5,000-char hard cap** (v4.5/v5/v5.5) | 3,000 was the v4-era cap. Quality sweet spot stays **~3,000** (~40-60 lines / 200-300 words) — past that Suno rushes, skips sections, or cuts output short. |
| Title | **~100 chars** | Up from ~80 in v4. No effect on musical output |
| Exclude field | Free-text in Advanced Options (Custom mode) | Same vocabulary as inline negatives |

**Verified 2026-07-18** — no official Suno page states field limits; figures are third-party tester consensus ([hookgenius character limits](https://hookgenius.app/learn/suno-character-limits/), [aimusicapi cheat sheet, 2026-07-03](https://aimusicapi.ai/en/blog/suno-ai-prompt-character-limits)).

### The lyrics field is a SECOND style channel

Power users treat the lyrics field as more than words to sing. **Per-section style overrides** in lyrics control instrumentation, dynamics, and production section-by-section — something the global style prompt can't do.

```
[Verse: piano only, no drums, intimate]
First narrative beat...
The vocals carry the weight...

[Pre-Chorus: drums enter, building]
Tension rising...
Tension rising...

[Chorus: full band kicks in, distorted guitar lead, gang vocals]
THE HOOK
THE HOOK

[Bridge: stripped to vocals + acoustic, dry mix]
Most vulnerable moment...

[Chorus: bigger than before, double-tracked vocals, layered harmonies]
THE HOOK
```

Two separator syntaxes work — both on the same `[Tag]` line:

- `[Verse: descriptor, descriptor]` — colon + comma list
- `[Bridge | dark | introspective | sparse]` — pipe-separated

Keep modifiers short (2-4 words each). Match section to tone — "explosive drop" only makes sense on `[Drop]`, not `[Intro]`.

This solves the **dynamics problem** — without it, every section sounds the same density. With it, you can build verse-chorus contrast, strip the bridge, blow up the final chorus.

### Worked example (synth-pop)

**Style prompt:**

```
synth-pop, 80s-inspired, nostalgic and hopeful,
shimmering analog synths, warm Moog bass, punchy drum machine,
ethereal female vocals with reverb tail, 95 BPM,
polished radio-ready production, no autotune
```

**Lyrics (skeleton):**

```
[Intro]
[Verse 1]
First narrative beat, present tense, concrete imagery...

[Pre-Chorus]
Building tension, single-line repetition encouraged

[Chorus]
The HOOK — peak energy, full instrumentation
Repeat the title or core phrase

[Verse 2]
Second narrative beat, contrast or escalation

[Chorus]

[Bridge]
Contrast section — often a key change or stripped-back

[Chorus]
[Outro]
[End]
```

Negative prompts go at the **end** of the style prompt: `..., no autotune, no reverb wash`. The `Exclude` field in Custom mode's Advanced Options is the structural alternative.

### Anti-patterns (always flag these in `clean` action)

| Anti-pattern | Why it fails | Fix |
|--------------|--------------|-----|
| Vague genre (`pop`, `rock`) | Generic AI sound | Specify subgenre + era + tonal cue |
| 5+ stacked genres | Muddy mix, incoherent style | Pick 1-2 max, or use a clear hybrid (`nu-metal dubstep`) |
| 9+ mood words | Conflicting emotional signals | 2-3 related moods |
| `amazing`, `epic`, `beautiful` | Zero effect on output | Replace with acoustic descriptors (`raspy`, `breathy`, `intimate`) |
| BPM as descriptor (`fast`) | ±20 BPM drift | Use numeric (`128 BPM`) — ~90% adherence in v5.5 |
| `(x2)` after a lyric line | Repeat is largely ignored | Write the line twice with minor variation |
| Naming artists directly (`like Drake`) | Blocked or ignored | Use sound descriptors (`Toronto trap bounce`, `silk-smooth R&B falsetto`) |
| `no drums` in a drum-heavy genre alone | Drums still appear | Pair with positive (`piano only, no drums`) |
| Style prompt > 1000 chars | Silent truncation | Front-load critical content |
| Capitalize EVERY word | Effect dilutes | Cap only turning-point words for emphasis |
| Vocal descriptor + active Voices/Custom Model | Conflict between clone and prompt | **Drop gender/tone descriptors when a Voice or Custom Model is selected** |

### Custom mode is required for tag syntax

Simple mode = unified prompt + auto-lyrics. **Custom mode** = separate fields (style, lyrics, title) + Advanced Options + tag syntax + Creative Sliders. Any time the user wants `[Verse]`/`[Chorus]`/`[Female Vocal]`-style tags, they must be in Custom mode. See [context/advanced.md](context/advanced.md).

---

## How to handle each action

**`prompt <intent>`** — build both style and lyrics. Read [context/style.md](context/style.md) for layer detail, [context/lyrics.md](context/lyrics.md) for tag taxonomy. Produce two fenced blocks (style, lyrics), each labeled, within budget. End with 2-3 tweak suggestions.

**`lyrics <intent>`** — load [context/lyrics.md](context/lyrics.md). Output a tagged lyrics block with section structure (`[Verse 1]`, `[Chorus]`, etc.). Include 1-2 performance cues (parentheticals, ellipses) where they fit naturally. Stay ≤3,000 chars — the quality sweet spot; the hard cap is 5,000 — unless user asked for max.

**`style <intent>`** — load [context/style.md](context/style.md). Walk the 6-layer formula. Output one fenced style-prompt block + character count. Suggest 2-3 alternatives (different mood, different production).

**`clean <text>`** — load [context/troubleshoot.md](context/troubleshoot.md) and [context/style.md](context/style.md). Score the user's prompt against the anti-pattern table above. Surface flagged issues with specific quotes. Propose a rewrite. Do NOT silently rewrite — show the diff in reasoning.

**`tags`** — load [context/lyrics.md](context/lyrics.md). Render the full taxonomy as tables (structural, vocal, instrument, mood, ending). Include parameterized syntax `[Tag: descriptors]` example.

**`genre <name>`** — 4-mode router. Detect intent from arguments:

1. **Template mode** — `<name>` matches one of the 12 built-in templates (pop, rock, hip-hop, trap, edm, jazz, classical, folk, metal, ambient, lofi, rnb): read [templates/<name>.md](templates/) and present.

2. **Research mode** — `<name>` is a real genre but no template exists (e.g., `dungeon synth`, `witch house`, `gqom`, `phonk`, `slowcore`, `vaporwave`, `nu-disco`):
   - Check [context/genre-taxonomy.md](context/genre-taxonomy.md) first — if cataloged, build a Suno prompt from the catalog entry
   - If not cataloged, invoke the `research` action's Phase 1 (WebFetch / Perplexity) to fetch BPM range, instrumentation, vocal style, production character
   - Synthesize into the standard template format: style prompt block + lyrics shell + 3 tweak knobs + 2-3 common variants
   - Cite sources

3. **Suggest mode** — `<name>` starts with `suggest` (e.g., `genre suggest dark moody chill`, `genre suggest dystopian aggressive`) OR is a vibe phrase rather than a genre name:
   - Read [context/genre-taxonomy.md](context/genre-taxonomy.md) "Vibe → genre mapping" section
   - Return 3-7 fitting genres, each with: 1-line distinguishing characteristic + the right BPM/key/instrumentation hints + which template to load OR which research target to chase
   - Ask user which one to expand into a full prompt

4. **Family mode** — `<name>` starts with `family` (e.g., `genre family hip-hop`, `genre family electronic`):
   - Read [context/genre-taxonomy.md](context/genre-taxonomy.md) family tree
   - Show the requested family's subgenres in tree form
   - Brief 1-line characteristic per subgenre
   - Ask user which leaf to expand

If `<name>` is ambiguous (could be template OR research OR suggest), ask user which mode they want.

**`troubleshoot <symptom>`** — load [context/troubleshoot.md](context/troubleshoot.md). Match the symptom to a known failure mode. Give diagnosis + 1-3 specific fixes + a regenerate-with-this prompt rewrite if applicable.

**`tips`** — load [context/tips.md](context/tips.md). Surface community-validated techniques (caps for vocal pressure, vowel stretching for melisma, ellipses for breath, parentheticals for inline directives, hyphenation for staccato, line breaks for melodic separation). Caveat: MEDIUM-confidence — consensus across multiple community sources but no official Suno doc.

**`features`** — load [context/v55-features.md](context/v55-features.md) (what's new in v5.5) and/or [context/advanced.md](context/advanced.md) (modes, Personas, Cover, Extend, Replace Section, Stems, Sliders, Studio). Pick the section the user asked about — don't dump everything.

---

## Confidence flags (be honest about source quality)

- **HIGH confidence**: claims confirmed by Suno's official help center (`help.suno.com`) or `suno.com/blog`. The 6-layer formula, structural and vocal tag names, Custom mode requirements, Voices/Custom Models/My Taste mechanics, Creative Slider behavior — all HIGH. Character budgets are NOT officially published — third-party tester consensus only (MEDIUM-HIGH).
- **MEDIUM confidence**: community-validated techniques across multiple guides + Reddit consensus, but no official Suno doc. Capitalization weighting magnitude, vowel-stretching letter counts, hyphenation staccato, `(x2)` failure mode — all MEDIUM. Effects are real (multi-source agreement); exact magnitudes are folk wisdom.
- **Re-verified 2026-07-18 — position flipped since the 2026-05-10 pass**: current third-party testers agree the lyrics **hard cap is 5,000 chars on v4.5/v5/v5.5**; 3,000 was the v4-and-earlier cap. The earlier "3,000 consensus" conflated the old cap with the quality threshold. **~3,000 remains the practical budget** — past it Suno rushes, skips sections, or shortens output. Sources: [hookgenius character limits](https://hookgenius.app/learn/suno-character-limits/), [aimusicapi cheat sheet, 2026-07-03](https://aimusicapi.ai/en/blog/suno-ai-prompt-character-limits). No official Suno page states field limits.

When generating prompts, default to HIGH-confidence techniques. Surface MEDIUM-confidence tricks as opt-in suggestions, not commands.

---

## What this skill does NOT do

- **Generate audio** — Suno does that. This skill produces text prompts.
- **Cover legacy v4 prompting** — the ~200-char style-prompt era is out of scope. Targets v5.5.
- **Make commercial-use determinations** — Cover and Voices have commercial constraints noted in `context/advanced.md`; treat as informational, not legal advice.
- **Replace Suno's web UI workflow** — this is a prompt-craft assistant. Workflow steps requiring clicks in Suno's UI (Replace Section, Persona creation, Voice verification) are described, not automated.
- **Fix already-generated audio** — Suno's prompt is a generation-time control. Most issues (hallucinated lyrics, vocal artifacts, BPM drift) are prevention-only. The skill's troubleshoot action gives the prompt-side fix, then asks the user to regenerate.
