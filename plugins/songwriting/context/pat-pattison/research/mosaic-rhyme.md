# Mosaic Rhyme — Multi-Word Combos Across Parts of Speech

Pat Pattison — *Pat Pattison's Songwriting: Essential Guide to Rhyming*
(2014), Chapter 1 — taxonomy alongside masculine and feminine. Extended by
Pat's columns + Coursera Module 3 and by hip-hop / rap craft tradition
(Eminem, Sondheim, Lin-Manuel Miranda) which Pat references frequently.

**Mosaic rhyme is a rhyme where one (or both) of the rhyming units is
COMPOSED OF MULTIPLE WORDS.** The rhyme works on stressed-vowel + post-
vowel-consonant identity; the words being combined to produce that sound
can cross parts of speech, mix proper nouns, slang, contractions, and
phrase fragments.

Mosaic rhyme is a tier the AI routinely skips. Generic LLM defaults pull
single-word rhymes from a single part of speech (noun rhymes with noun,
verb with verb) and miss the multi-word territory entirely. Mosaic
SURFACE IS MANDATORY for any rhyme suggestion task per
[response-filter](response-filter.md) §1.

## What mosaic rhyme is

**Single word ↔ multi-word combo:**

| Source word | Mosaic partner | Construction |
|---|---|---|
| `Texas` | `wrecks us` | verb + object pronoun |
| `spaghetti` | `let me get a` | imperative phrase |
| `wedding` | `fed him` | verb + pronoun |
| `delicate` | `tell a kid` | imperative + object |
| `lyrical` | `miracle` (near-perfect) plus mosaic-stacks like `it'd be a` | hesitant filler phrase |
| `Pat Pattison` | `that's a fashion` (paraphrase example) | name → demonstrative + noun |

**Multi-word combo ↔ multi-word combo:**

| Side A | Side B | Both sides decompose |
|---|---|---|
| `tell us` | `jealous` | imperative+pronoun ↔ adjective |
| `up against` | `whiff incense` | adverb-phrase ↔ verb-noun |
| `looking for me` | `hooked on tea` | participle-prep-pronoun ↔ adjective-prep-noun |

The pattern: stressed-vowel identity + post-vowel-consonant identity (or
family / additive / kissin'-cousin tier per
[rhyme-types](rhyme-types.md)) holds across the SOUND of the multi-word
unit, not across the grammar.

## Cross-part-of-speech is the point

Standard rhyme search defaults to: noun → noun, verb → verb. Mosaic
rhyme breaks that. The freedom comes from:

| Source category | Mosaic partner can be |
|---|---|
| Noun (concrete) | verb + pronoun, adjective + noun, preposition + noun, adverb phrase, exclamation, proper-noun phrase |
| Verb | noun + verb, verb + adverb, contraction-stack, idiom fragment |
| Adjective | imperative phrase, dependent clause head, prepositional phrase |
| Proper noun | demonstrative + noun, verb + object, location phrase, slang phrase |
| Abstract noun (love, hope) | concrete imperative, sense-bound action phrase, sound effect |

The grammar mismatch is FEATURE, not bug. It creates surprise. Surprise
is what makes a rhyme land instead of slide.

## Proper nouns are mosaic-rich

Proper nouns rhyme MOSAIC-FIRST because:

1. Proper nouns rarely have direct rhyme partners (`Texas` has few
   single-word rhymes; `wrecks us` opens the field)
2. They have established stress patterns (`Téx-as`, `Lóu-i-si-a-na`)
3. They carry semantic weight per the song's developed world (per
   [rhyme-generation](rhyme-generation.md) Step 6) — using a place / name
   in rhyme position cements the world

Mosaic-friendly proper-noun categories:

- **Place names:** city / town / state / country / street / venue /
  landmark — these almost always need a mosaic partner
- **Person names:** first names, last names, full names, nicknames
- **Brand / product names:** when the song's world uses them
- **Era / event names:** decade, year, season, holiday
- **Cultural references:** song titles, movie titles, book titles
  (carefully — copyright/cliche aware)

## Hip-hop / rap craft tradition

Mosaic rhyme is the dominant tier in rap and hip-hop. Pat references this
explicitly in his columns and Coursera material. Eminem's interview with
Anderson Cooper is canonical: he diagrammed mosaic rhyme chains for words
"impossible" to rhyme by showing multi-word decomposition.

Examples of the kind of stacked mosaic move (paraphrased for IP):

- Source: `orange` → mosaic chains using `door hinge`, `four-inch`,
  `pour ink` (stressed vowel + family/additive consonant)
- Source: `purple` → mosaic chains using `circle`, `hurts you'll`
- Source: `month` → mosaic chains using `once a`, `lunch a`,
  `dunce-uh` (filler / nonsense word in the chain)

The rap tradition treats every word as rhyme-able by decomposing the
sound and reassembling from multi-word combos. Pat names this discipline
in *Essential Guide to Rhyming* (2014), Chapter 1.

## Where mosaic rhyme is generated in the worksheet

When running the three-stage worksheet (per
[rhyme-worksheets](rhyme-worksheets.md)):

1. **Stage 1 — Focus.** Same as standard.
2. **Stage 2 — Idea words.** Same as standard.
3. **Stage 3 — Rhyme search.** Add a MOSAIC COLUMN per seed word:
   - Single-word perfect / family / cousin (standard columns)
   - **Mosaic single-side (source word ↔ multi-word combo)**
   - **Mosaic both-side (multi-word combo ↔ multi-word combo)**
   - Cross-part-of-speech mosaic candidates
   - Proper-noun mosaic candidates (if the song's world allows)
   - Slang / contraction / phrase-fragment mosaic candidates

The mosaic column generates 5-15 candidates per seed word in addition to
the standard tiers. Stressed-vowel anchor identification + identity check
still apply.

## Identity check for mosaic rhyme

Pat's three-condition rhyme test applies per stressed vowel, not per
word boundary. For mosaic:

- **Vowel identity** — the stressed vowel of the LAST stressed syllable in
  the multi-word unit must match the source's stressed vowel (or family /
  cousin per tier)
- **Post-vowel consonant identity** — the consonant after the stressed
  vowel of the last word in the multi-word unit must match (or family /
  cousin per tier)
- **Pre-vowel consonant DIFFERENCE** — the pre-vowel consonant of the
  rhyming syllable must DIFFER. Identity rule does NOT pre-empt across
  the multi-word boundary.

Example identity-fail: `Texas` ↔ `text us`. The stressed vowel and post-
vowel consonant match (`ĕks` + nothing distinct after), BUT the pre-vowel
consonant `t-` is IDENTICAL on both sides. This is identity in disguise,
not rhyme. The mosaic-rhyme identity check must catch this.

Example identity-pass: `Texas` ↔ `wrecks us`. Pre-vowel `t` vs `r` — DIFFER.
Rhyme accepted.

## Stress pattern preservation

Mosaic rhymes must preserve the stress count and rhythm of the source
line's rhyme position. If the source word has 2 syllables with stress on
the first (`Téx-as`), the mosaic partner must scan the same way
(`wrécks-us`). If the line's meter calls for 2 syllables, a 3-syllable
mosaic doesn't fit no matter how clever.

Stress paradigms apply across word boundaries:

| Source | Stress pattern | Acceptable mosaic | Unacceptable |
|---|---|---|---|
| `Téx-as` (X.) | trochee | `wrécks-us` (X.) | `whatever wrecks us` (..X.) |
| `de-cíde` (.X) | iamb | `the bríde` (.X) | `here is the bride` (...X) |
| `só-li-ta-ry` (X..X) | dactyl-trochee | `só-lemn ma-ry` | `the so-lem-ni-ty` |

The meter scan (per [meter](meter.md)) is the gate. Mosaic that breaks
meter does not earn its place in a hot spot.

## Mosaic risk register

Mosaic rhyme has failure modes:

| Risk | What it looks like | Correction |
|---|---|---|
| Phrase-containing-source-word default | Source `around` → list emits `sleep around`, `push me around`, `let me down`, `kicked around`, `messed around` — every "mosaic" reuses the source word itself with a prefix. That's identity-with-prefix, NOT mosaic. Common LLM failure mode (defaults to search-and-find-phrase rather than sound-decomposition). | Decompose source SOUND first (stressed vowel + post-vowel consonants), then assemble a multi-word unit whose SYLLABLES match — WITHOUT reusing the source word. For `around` /əˈraʊnd/ → mosaic candidates = `the sound`, `the ground`, `they found`, `renowned`, `a hound` — multi-word units whose stressed syllable matches /aʊnd/ via different lexical content. |
| Forced contraction | `gonna get a` for `agenda` — feels squeezed | Either earn the colloquial register or pick a non-contraction partner |
| Cute over earned | `lyrical / it'd be a miracle` when the song isn't playful | Match register to song; cute mosaic in a serious song reads as posturing |
| Identity-in-disguise | Pre-vowel consonant repeats across the word boundary | Re-run identity check on the SOUND, not the spelling |
| Meter-break | Mosaic adds extra syllables outside the source's stress count | Sing-check; trim or replace |
| Distracting from meaning | The mosaic move pulls attention from the line's content | The rhyme should serve the line, not perform |
| Hot-spot misplacement | Mosaic landed in a verse-middle line, not a hot spot | Place mosaic moves in section-end positions where craft can be seen |

## When mosaic rhyme is the RIGHT call

- Source word has few single-word partners (proper nouns, polysyllabic
  abstractions, words ending in rare consonant clusters)
- The song's register is playful, conversational, or hip-hop-adjacent
- A specific cliche-pair needs breaking and the mosaic provides a fresh
  partner
- The song's world includes places / characters / brands that NEED to
  appear in rhyme position (cement the world)
- The writer wants the rhyme to feel surprising rather than expected
- The writer wants prosodic forward motion via UNEXPECTED resolution

## When mosaic rhyme is the WRONG call

- The song's register is hymn-formal, classical, or strictly traditional
- The rhyme position calls for closure / landing (a slick mosaic feels
  unstable when stability is wanted)
- The mosaic move would break the line's stress paradigm
- Better single-word options exist that serve the song's emotion better
- The mosaic feels like a parlor trick rather than craft

Per [rhyme-strategy](rhyme-strategy.md) decision matrix: pick the tier
that serves emotional intent. Mosaic is one tier; not a default.

## Surfacing mosaic to the writer

The AI surfaces mosaic candidates in the standard rhyme list (per
[rhyme-generation](rhyme-generation.md) Step 8) BUT labels them as
mosaic and shows the decomposition:

```
Stressed vowel: ĕ-ks (as in "Texas")

Perfect (single-word, fully resolved):
- (few; Texas is mosaic-territory)

Mosaic (multi-word, cross-POS, proper nouns OK):
- wrecks us            — verb + pronoun;  closure / stable
- texts us             — REJECT, pre-vowel identity
- next bus             — adj + noun; openness / unstable
- vexed us             — verb + pronoun; closure / kinetic
- complex thus         — adj + adverb; closure / formal
- exits abruptly       — noun + adverb; semi-resolved
- Lex Luthor (sort of) — proper noun; comic register; risky
- bet on us            — verb-phrase; closure / earnest
- check our            — verb + possessive; openness
- decked us            — verb + pronoun; closure / kinetic

From the song's world:
- [pulls per the song's setting / character / era]
```

Each mosaic candidate gets:

- The decomposition shown
- A POS / phrase-type label
- Closure / openness signal
- Cliche-risk if any
- Register fit signal

## Examples by source type

### Common nouns

| Source | Mosaic options (illustrative, paraphrased; check identity + meter per song) |
|---|---|
| `mother` | `another`, `smother her`, `recover`, `discover` (non-mosaic), `love her`, `above her`, `shove her` |
| `morning` | `warning`, `forming`, `storming`, `for me`, `floor me`, `more please`, `for any` |
| `silence` | `defiance` (non-mosaic), `find us`, `behind us`, `try us`, `fly us`, `science class`, `try once` |

### Abstract nouns

| Source | Mosaic options |
|---|---|
| `love` | `enough`, `tough`, `above`, `shove`, `cuff`, `huff`, `out of`, `done with`, `had enough of` |
| `time` | `rhyme`, `prime`, `chime`, `crime`, `find me`, `mind me`, `behind me`, `dime store`, `climb fence` |
| `hope` | `slope`, `rope`, `scope`, `nope`, `pope`, `mope`, `going to cope`, `start to grope`, `at the end of our rope` |

### Proper nouns (place)

| Source | Mosaic options |
|---|---|
| `Nashville` | `cash bill`, `last drill`, `bash will`, `dash, still`, `mash skill`, `crash hill` |
| `Texas` | `wrecks us`, `vexed us`, `next bus`, `check fuss`, `Lexus` (single-word), `complex thus` |
| `New Orleans` | `you been means`, `you've been screens`, `blue jeans`, `clue queens`, `you sing leans` (forced) |

### Proper nouns (person)

| Source | Mosaic options |
|---|---|
| `Mary` | `weary`, `dreary`, `dairy`, `marry me`, `parry me`, `tarry, leave`, `bury me`, `it scary` |

Proper nouns in rhyme position lock the song's world to a specific place
/ person. This is a feature when the world is established; a liability
when the proper noun has not yet earned its mention.

## Cross-references

- [rhyme-generation](rhyme-generation.md) — internal rhyme-generation
  discipline; Step 8 surfacing includes mosaic
- [rhyme-types](rhyme-types.md) — stability tiers apply within mosaic
- [rhyme-fundamentals](rhyme-fundamentals.md) — identity check applies
  across word boundary
- [rhyme-strategy](rhyme-strategy.md) — when to deploy mosaic by
  emotional intent
- [response-filter](response-filter.md) §1 — mandatory mosaic-tier check
- [line-brainstorm](line-brainstorm.md) — Column 1 includes mosaic
- [meter](meter.md) — stress paradigm preserved across word boundary
- [cliche](cliche.md) — friendly cliche test applies to mosaic too
- [object-writing](object-writing.md) — song's developed world feeds the
  mosaic worth pulling from

## Anchor stance

> "Songs are made for ears, not eyes." — Pat Pattison
> (*Essential Guide to Rhyming* (2014), Introduction)

> "Rhyme creates a sonic roadmap: it tells those eyeless ears where to
> go and when to stop." — Pat Pattison
> (*Essential Guide to Rhyming* (2014), Introduction, paraphrased ≤25w)

Mosaic rhyme works because the ear hears the SOUND, not the spelling or
the part of speech. Pat's craft applies the same identity check + tier
walk + cliche scan to multi-word units. The AI must surface this tier
or it has under-served the song.
