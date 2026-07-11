# Line / Section Brainstorm — Narrow-Focus High-Volume Dump

Single line stuck. Single section thin. Writer needs RAW MATERIAL — many
options, fast, filtered through Pat's discipline, before the revision pass.

This is NOT the same as:

| Action | Volume | Output shape |
|---|---|---|
| `/pat-pattison rhyme` / `rhyme-generation` | 8-15 rhyme candidates | rhyme-list per tier |
| `/pat-pattison variations` | 5-7 labeled line alternates | menu of polished alternates |
| `/pat-pattison line-brainstorm` | 30-50+ across 5 columns | RAW pre-revision dump |
| `/pat-pattison demo` | diagnosis of the line in song context | dominant-problem named |
| `/pat-pattison audit` | pre-lock checklist on a candidate line | go / no-go signal |
| `/pat-pattison object-writing` | timed sense-bound write | raw-image generation |

`line-brainstorm` is the *between* tool — the writer knows the line needs
to change but doesn't know what to change. Generate MANY options, sort
later. The discipline applies (per [response-filter.md](response-filter.md)
§1 + §2 + §7), but volume comes first; selection comes second.

## When the writer reaches for this

Trigger phrases the AI should hear:

- "I need 30 alternatives for this line"
- "more options for the last line of the chorus"
- "what could replace 'lonely' here"
- "what else could go here"
- "this line isn't right but I don't know why"
- "give me a big list of options"
- "let me see a bunch of swaps"
- "more end-line words"
- "all the words that could rhyme AND mean something"
- "what's the section saying — give me more ways to say it"

If the writer says "the perfect alternative" or "the best one" — that's
`/variations`, not `line-brainstorm`. Brainstorm is volume; variations is
curation.

## Two scope levels

### Scope A — ONE LINE

The writer points at a specific line. Generate across FIVE COLUMNS:

1. **End-line word swaps** (~30) — words that could replace the current
   end-line word, organized by stability tier (perfect / family / additive-
   subtractive / assonance / consonance / **mosaic — multi-word combos
   across parts of speech, proper nouns OK** / from the song's developed
   world). Mosaic tier is MANDATORY per
   [response-filter](response-filter.md) §1 — at least 5 candidates from
   [mosaic-rhyme.md](mosaic-rhyme.md) per source word.
2. **Content-word swaps** (~10) — the line's load-bearing word (usually
   a verb, sometimes an image-noun) replaced with stronger / more
   specific / more surprising alternatives
3. **Internal rhyme partners** (~10) — mid-line sonic-bonding candidates
   (assonance + consonance + alliteration with words inside the line)
4. **Image / sense alternates** (~10) — Rusty's-Collar concrete-image
   replacements for any abstraction in the line, with sense labels
   (sight / hearing / smell / taste / touch / organic / kinesthetic)
5. **Whole-line variants** (~5) — line shapes that preserve the line's
   functional job (closes the section / sets up the next line / lands
   the title) while varying everything else

### Scope B — ONE SECTION

The writer points at a verse / chorus / bridge / refrain / transitional
bridge. Run Scope A FOR EACH LINE. Then add:

1. **Stability profile audit** — name the section's lyric stability
   pattern (stable / unstable / mixed); note which line carries which
   weight; flag mismatches with Pat's section-type expectations (per
   [audit-checklist.md](audit-checklist.md))
2. **Hot-spot map** — where does the title sit? where does the punchline
   sit? line 1 of section and last line of section noted
3. **Box-model column check** if this is a verse — does this verse
   inhabit a different You-I-We / Past-Present-Future box than its
   neighbors? (per [box-model.md](box-model.md))

## Discipline (filtered through response-filter.md)

The brainstorm is fast and high-volume, but NOT undisciplined. Pre-dump:

- [ ] **Stressed vowel of the end-line word identified** before Column 1
- [ ] **Identity check** applied (rejected before listing)
- [ ] **Cliche scan** applied per pair / per candidate (flag, don't
      always reject — but flag)
- [ ] **Song's developed world** mined for Column 1 when the song has
      established setting / era / character — ≥5 candidates from THAT
      vocabulary
- [ ] **Stress-count match** noted per column (most lines want a specific
      stress count to fit the meter — flag candidates that break it)
- [ ] **Sense-coverage** for Column 4: all 7 senses scanned, not just the
      obvious 2-3
- [ ] **Stability tier label** for Column 1 candidates
- [ ] **Verb-strength rating** for Column 2 verbs (weak / working /
      surprising)

Post-dump:

- [ ] **No single winner imposed** — the writer picks
- [ ] **Top-3 suggestions per column** offered separately AS A SUGGESTION,
      not a verdict — labeled with the craft reason
- [ ] **Hand-off** to `/variations` if the writer wants 5-7 polished
      alternates next, or `/audit` for pre-lock check

## Output format

```
LINE BRAINSTORM — "<the current line verbatim>"

Source: <verse 1 line 3 / chorus last line / etc.>
Function: <closes the section / sets up the chorus / lands the title>
Stress count: <N stresses>
Stressed end-line vowel: <vowel>
Current end-line word: <word>

──────────────────────────────────────────────
Column 1 — END-LINE WORD SWAPS (30 across tiers)
──────────────────────────────────────────────
Perfect (fully resolved, identity passed):
  - <word> — <syllable count>; cliche-pair risk: low / med / high
  - <word> — ...
  (~5 candidates)

Family (post-vowel consonant family-related):
  - <word> — partner/companion; ...
  (~5 candidates)

Additive / subtractive (one consonant added/removed):
  - <word> — additive on <consonant>; ...
  (~4 candidates)

Assonance (vowel-only match):
  - <word> — different post-vowel; ...
  (~4 candidates)

Consonance (post-vowel-only match, different vowel):
  - <word> — vowel shift to <vowel>; ...
  (~3 candidates)

MOSAIC (multi-word, cross-POS, proper nouns OK):
  - <word combo> — POS decomposition; identity-checked across boundary
  - <word combo> — ...
  (≥5 candidates; more when source is proper noun or rare ending)

From the song's developed world:
  - <world-word> — <why it fits>; proper-noun mosaic if applicable; ...
  (~5 candidates)

──────────────────────────────────────────────
Column 2 — CONTENT-WORD SWAPS (~10)
──────────────────────────────────────────────
Current content word: <word>  [weak / working / surprising]
Verb swaps if applicable:
  - <verb> — wattage rating; ...
Noun-image swaps if applicable:
  - <noun> — specificity / sense / surprise; ...

──────────────────────────────────────────────
Column 3 — INTERNAL RHYME PARTNERS (~10)
──────────────────────────────────────────────
Assonance partners within the line:
  - <word A> and <word B in the line> share <vowel>; ...
Consonance partners:
  - ...
Alliteration:
  - ...

──────────────────────────────────────────────
Column 4 — IMAGE / SENSE ALTERNATES (~10)
──────────────────────────────────────────────
Replaces any abstraction in the line with concrete sense-bound image:
- sight: <image>
- hearing: <image>
- smell: <image>
- taste: <image>
- touch: <image>
- organic: <image>
- kinesthetic: <image>

──────────────────────────────────────────────
Column 5 — WHOLE-LINE VARIANTS (~5)
──────────────────────────────────────────────
Each preserves the function (close the section / set up the next line /
land the title) but varies content, image, or rhyme partner:

1. <whole line> — <what changed / what it costs / what it gains>
2. <whole line> — ...
3. <whole line> — ...
4. <whole line> — ...
5. <whole line> — ...

──────────────────────────────────────────────
SUGGESTIONS (not verdicts)
──────────────────────────────────────────────
Top-3 most-promising directions across the columns:
1. <direction> — reason
2. <direction> — reason
3. <direction> — reason

Cliche flags to watch:
- <pair> if used together
- <phrase> in any whole-line variant

Hand-off:
- /variations <line> — for 5-7 polished alternates
- /audit <line> — for pre-lock check on a chosen candidate
- /rhyme-generation - for more rhyme tiers if Column 1 felt thin
```

## Section-level output additions

Append:

```
──────────────────────────────────────────────
STABILITY PROFILE — <section type>
──────────────────────────────────────────────
Expected stability for <verse/chorus/bridge/refrain/transitional-bridge>:
  - <expected pattern per audit-checklist.md>
Current section's stability pattern (line-by-line):
  - Line 1: stable / unstable — reason
  - Line 2: ...
Mismatch flags:
  - <line>: <what's off>

──────────────────────────────────────────────
HOT-SPOT MAP
──────────────────────────────────────────────
- Section line 1: <strong content word at start?>
- Section last line: <title or punchline-grade content?>
- Title placement in section: <line N>

──────────────────────────────────────────────
BOX-MODEL CHECK (if verse)
──────────────────────────────────────────────
- Verse N inhabits which box: You-I-We / Past-Present-Future
- Neighbors' boxes: <verse 1 box, verse 3 box>
- Travelogue risk: <yes / no — name the test>
```

## Coach posture during the dump

Per [coaching-protocol.md](coaching-protocol.md):

- Surface the columns
- Name the TOP-3 directions as suggestions (per craft reason)
- Ask the writer which direction feels closest to the song's pull
- Hand off to the appropriate next action when the writer commits

Do NOT make the writer wade through 50 unlabeled options. Per-column
labels + top-3 suggestions + hand-off route. Volume + curation.

## Anchor quotes

> "Verbs are the amplifiers of language. The difference between great
> writers and average writers is almost always in their verbs."
> — Pat Pattison (Unpaved interview)

> "Eminem and Stephen Sondheim approach their writing through the same
> process. It's called a worksheet process."
> — Pat Pattison (American Blues Scene interview)

The brainstorm IS the worksheet process applied to a single line.

## Cross-references

- [rhyme-generation.md](rhyme-generation.md) — internal rhyme discipline
  (Column 1 backend)
- [rhyme-types.md](rhyme-types.md) — stability scale + family taxonomy
- [rhyme-sonic-bonding.md](rhyme-sonic-bonding.md) — internal rhyme +
  vowel triangle (Column 3 backend)
- [object-writing.md](object-writing.md) — sense-bound image generation
  (Column 4 backend)
- [cliche.md](cliche.md) — cliche taxonomy + friendly-cliche test
- [variations.md](variations.md) — 5-7 polished alternates (next action
  after brainstorm)
- [audit-checklist.md](audit-checklist.md) — pre-lock check
- [response-filter.md](response-filter.md) — filter discipline applied
  before / during / after the dump
- [box-model.md](box-model.md) — verse division of labor for section-level
  brainstorm
