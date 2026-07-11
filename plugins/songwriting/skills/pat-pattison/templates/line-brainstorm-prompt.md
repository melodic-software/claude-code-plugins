# Line / Section Brainstorm Prompt Template

Use this template when the writer asks for HIGH VOLUME options for ONE
line or ONE section. Per [line-brainstorm.md](../research/line-brainstorm.md)
and [response-filter.md](../research/response-filter.md) §1 + §2 + §7.

## When to use this template

- Writer says "30 alternatives for this line"
- Writer says "more options for the chorus"
- Writer says "what else could go here"
- Writer says "I don't know what to do with this line"
- Writer says "give me a big list"
- Pre-revision dump, NOT polished alternates

Not for: rhyme-only search (use `rhyme-generation`), 5-7 polished
alternates (use `variations`), or single-rhyme lookup (use `rhyme`).

## Pre-flight checklist (run before generating)

- [ ] Section type identified (verse / chorus / bridge / refrain /
      transitional bridge)
- [ ] Line function named (closes section / sets up next / lands title /
      builds tension / repaints chorus)
- [ ] Stress count of the current line counted
- [ ] Stressed vowel of the current end-line word identified
- [ ] Song's developed world summarized (setting / era / character /
      proper nouns) — feeds the world-vocabulary column
- [ ] Cliche pairs flagged to avoid

## Template output

```
LINE BRAINSTORM — "<the line verbatim>"

Source: <section> <line N>
Function: <closes / sets up / lands title / etc.>
Stress count: <N>
Stressed end-line vowel: <vowel>
Current end-line word: <word>
Song world: <one-line summary>

──────────────────────────────────────────────
COLUMN 1 — END-LINE WORD SWAPS
──────────────────────────────────────────────

Perfect / fully resolved (single-word; identity passed):
  - <word> — cliche-pair risk: <low/med/high>
  - <word> —
  - <word> —
  - <word> —
  (~5)

Family (post-vowel consonant family-related):
  - <word> — partner/companion + family
  - <word> —
  (~5)

Additive / subtractive (one consonant added/removed):
  - <word> — additive on <consonant>
  - <word> —
  (~4)

Assonance (vowel-only match, different post-vowel):
  - <word> — assonance; openness signal
  - <word> —
  (~4)

Consonance (post-vowel-only match, different vowel):
  - <word> — consonance; deceleration signal
  - <word> —
  (~3)

MOSAIC (multi-word, cross-POS, proper nouns OK) — MANDATORY:
  - <word combo> — POS decomposition; identity-checked
  - <word combo> —
  - <word combo> —
  - <word combo> —
  - <word combo> —
  (≥5; more if source is proper noun or rare ending)

From the song's developed world:
  - <world-word or world-mosaic> — why it fits the song
  - <world-word> —
  (~5)

──────────────────────────────────────────────
COLUMN 2 — CONTENT WORD SWAPS
──────────────────────────────────────────────

Current load-bearing content word: <word>  [weak / working / surprising]

If the load-bearing word is a VERB:
  - <verb> — wattage rating (per Pat's verbs-as-amplifiers principle)
  - <verb> —
  - <verb> —
  (~5 verb candidates, ranked by surprise / specificity)

If the load-bearing word is a NOUN-IMAGE:
  - <noun> — specificity gain
  - <noun> — sense gained
  - <noun> — surprise gained
  (~5)

If the load-bearing word is an ABSTRACTION:
  - REPLACE with sense-bound image (route to Column 4 image alternates)

──────────────────────────────────────────────
COLUMN 3 — INTERNAL RHYME PARTNERS
──────────────────────────────────────────────

Inside-line sonic-bonding candidates per
[rhyme-sonic-bonding.md](../research/rhyme-sonic-bonding.md):

Assonance partners within the line:
  - <existing line word> + <new word> share <vowel>
  - ...
  (~3)

Consonance partners:
  - <existing line word> + <new word> share <consonant>
  - ...
  (~3)

Alliteration (initial / medial / terminal / concealed):
  - <existing line word> + <new word>
  - ...
  (~3)

──────────────────────────────────────────────
COLUMN 4 — IMAGE / SENSE ALTERNATES
──────────────────────────────────────────────

Replaces any abstraction with concrete sense-bound image. All 7 senses
scanned (sight / hearing / smell / taste / touch / organic / kinesthetic):

- sight: <concrete image from song's world>
- hearing: <concrete image>
- smell: <concrete image>
- taste: <concrete image>
- touch: <concrete image>
- organic (internal body — heartbeat, breath, gut): <image>
- kinesthetic (motion / balance / weight): <image>

Rusty's Collar replacement candidates if the line currently TELLS:
  - <concrete image that shows what the line is telling>
  - ...

──────────────────────────────────────────────
COLUMN 5 — WHOLE-LINE VARIANTS
──────────────────────────────────────────────

Each variant preserves the line's function (close / set up / land title /
build tension / repaint) but varies content, image, or rhyme partner:

1. <whole line> — change made / cost / gain
2. <whole line> — change made / cost / gain
3. <whole line> — change made / cost / gain
4. <whole line> — change made / cost / gain
5. <whole line> — change made / cost / gain

──────────────────────────────────────────────
SUGGESTIONS (not verdicts)
──────────────────────────────────────────────

Top-3 most-promising directions across the columns:

1. <direction> — Pat's craft reason
2. <direction> — Pat's craft reason
3. <direction> — Pat's craft reason

Cliche flags to watch:
- <pair or phrase>
- <pair or phrase>

Identity-disguise flags caught (rejected):
- <rejected candidate> — pre-vowel consonant identical

Hand-off:
- `/variations <line>` — for 5-7 polished alternates
- `/audit <line>` — for pre-lock check on a chosen candidate
- `/rhyme-generation` — for more rhyme tiers if Column 1 felt thin
- `/mosaic <word>` — for deeper mosaic search if Column 1 mosaic was rich
```

## Section-level template additions

When the writer asks for a whole SECTION (Scope B per
[line-brainstorm.md](../research/line-brainstorm.md)), run the 5-column
template for each line, then append:

```
──────────────────────────────────────────────
STABILITY PROFILE — <section type>
──────────────────────────────────────────────

Expected stability pattern for this section type (per audit-checklist.md):
  - <pattern>

Current section's stability pattern (line-by-line):
  - Line 1: stable / unstable — reason
  - Line 2: ...
  - Line N: ...

Mismatch flags:
  - <line>: <what's off>

──────────────────────────────────────────────
HOT-SPOT MAP
──────────────────────────────────────────────

- Section line 1: strong content word at start? <yes / no — what's there>
- Section last line: title or punchline-grade content? <yes / no>
- Title placement in section: line <N>
- Phrase-internal hot spots: 2nd-most-important word at phrase
  beginning? most-important at end?

──────────────────────────────────────────────
BOX-MODEL CHECK (if verse)
──────────────────────────────────────────────

- Verse N inhabits which box: <You-I-We / Past-Present-Future column>
- Neighbors' boxes:
  - Verse <N-1>: <box>
  - Verse <N+1>: <box>
- Travelogue risk: <yes / no — name the diagnostic>

──────────────────────────────────────────────
TRIGGER LINE CHECK (line-before-chorus)
──────────────────────────────────────────────

Per *Writing Better Lyrics* (2009), Chapters 7 + 24:
- Current trigger line: <line>
- Does it set up the chorus's emotional ground?
- 3 trigger-line variants to test:
  1. <variant>
  2. <variant>
  3. <variant>
```

## Coach posture

Per [coaching-protocol.md](../research/coaching-protocol.md):

- Surface the columns; do NOT pick a single winner
- Name the TOP-3 directions as suggestions with Pat's craft reason
- Ask the writer which direction feels closest to the song's pull
- Hand off to specialized action when the writer commits

The brainstorm is volume; the curation is dialog.

## Anchor stance

> "Eminem and Stephen Sondheim approach their writing through the same
> process. It's called a worksheet process."
> — Pat Pattison (American Blues Scene interview)

The line-brainstorm IS the worksheet process applied to a single line.

## Cross-references

- [line-brainstorm.md](../research/line-brainstorm.md) — full mechanics
- [response-filter.md](../research/response-filter.md) — §1, §2, §7
  filter discipline
- [rhyme-generation.md](../research/rhyme-generation.md) — Column 1 backend
- [mosaic-rhyme.md](../research/mosaic-rhyme.md) — Column 1 mosaic tier
- [object-writing.md](../research/object-writing.md) — Column 4 backend
- [variations.md](../research/variations.md) — 5-7 polished alternates hand-off
- [coaching-protocol.md](../research/coaching-protocol.md) — dialog posture
