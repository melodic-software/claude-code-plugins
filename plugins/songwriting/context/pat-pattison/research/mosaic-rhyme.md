# Mosaic Rhyme — Multi-Word Combos Across Parts of Speech

Pat Pattison — *Essential Guide to Rhyming*
(2014), Chapter 1 — where mosaic rhyme is named and defined. Worked examples
run through Chapter 2 (the "risky business" walkthrough), Chapter 4 (feminine
family rhymes), and Chapter 6 (feminine assonance rhymes). Extended for
cross-part-of-speech search by Pat's columns + Coursera Module 3 and by
hip-hop / rap craft tradition — those extensions are marked as non-book where
they appear below.

**Mosaic rhyme is a rhyme where one (or both) of the rhyming units is
COMPOSED OF MULTIPLE WORDS.** The rhyme works on stressed-vowel + post-
vowel-consonant identity; the words being combined to produce that sound
can cross parts of speech, mix proper nouns, slang, contractions, and
phrase fragments.

> "Call these pairs above mosaic rhymes, since they are put together with
> syllables of different words, like stained glass pieces in a church window."
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 1

**Mosaic is a construction, not a third rhyme category.** This is the single
most-misread point in the taxonomy. Chapter 1 is explicit that "every rhyme is
either masculine or feminine. Never to both." A mosaic rhyme is still one or
the other — `commander/understand her` is feminine; `ap-pre-ci-ate/the quiche
he ate` is a three-syllable rhyme that Pat classifies as **masculine**, "since
[its] last syllable is more stressed than the one before it." Mosaic describes
*how the rhyming unit was assembled*, which is orthogonal to where its stress
falls. Never present mosaic as a peer of masculine and feminine.

Mosaic rhyme is a construction the AI routinely skips. Generic LLM defaults
pull single-word rhymes from a single part of speech (noun rhymes with noun,
verb with verb) and miss the multi-word territory entirely. Mosaic
SURFACE IS MANDATORY for any rhyme suggestion task per
[response-filter](response-filter.md) §1.

## Pat's own mosaic examples

These are the pairs Pat actually prints, with the chapter each comes from.
Treat them as the reference set; everything generated later in this file is
labeled as such.

| Mosaic pair | Type | How it is built | Source |
|---|---|---|---|
| `commander` / `understand her` | feminine | the unstressed tail is a pronoun, not an identity | Chapter 1 |
| `expand me` / `strand thee` | feminine | verb + object pronoun on both sides | Chapter 1 |
| `ap-pre-ci-ate` / `the quiche he ate` | masculine (three-syllable) | article + noun + pronoun + verb | Chapter 1 |
| `business` / `fizzless` | feminine | `fizz` from the masculine short `i` + `z` column, `less` from the masculine short `e` + `s` column | Chapter 2 |
| `business` / `quizless` | feminine | same construction, `quiz` from the same short `i` + `z` column | Chapter 2 |
| `travel` / `glass full` | feminine | noun + adjective read as one unit | Chapter 4 |
| `homely` / `phone me` | feminine | masculine word + pronoun `me` | Chapter 4 |
| `believer` / `please her` | feminine | verb + object pronoun `her` | Chapter 4 |
| `sailin'` / `tail him` | feminine | g-dropping opens the word to a verb + pronoun | Chapter 4 |
| `lonely` / `hold me` | feminine | transitive verb + `me` | Chapter 6 |
| `lonely` / `close me` | feminine | transitive verb + `me` | Chapter 6 |

Two generative rules fall straight out of that list:

1. **Masculine transitive verb + `me` / `her` / `him`.** Pat states it
   directly in Chapter 6: "One way is to use masculine transitive verbs plus
   the pronoun 'me'." This is the highest-yield mosaic construction in the
   book, and it works whenever the feminine target's unstressed syllable
   rhymes with a pronoun (Chapter 4).
2. **Drop the `g` on feminine `-ing` words.** "A neat trick: If the tone of
   your lyric is informal, you might try dropping the `g` on feminine 'ing'
   words, like 'sailing.' Then you can create a mosaic rhyme with 'him'"
   (Chapter 4).

## What mosaic rhyme is

**Single word ↔ multi-word combo** (generated candidates in the shape of Pat's
constructions — run identity and meter checks per song):

| Source word | Mosaic partner | Construction |
|---|---|---|
| `Texas` | `wrecks us` | verb + object pronoun |
| `spaghetti` | `let me get a` | imperative phrase |
| `wedding` | `fed him` | verb + pronoun |
| `delicate` | `tell a kid` | imperative + object |
| `lyrical` | `miracle` (near-perfect) plus mosaic-stacks like `it'd be a` | hesitant filler phrase |
| `lonely` | `hold me` | transitive verb + pronoun — **Pat's own**, Chapter 6 |

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

**Mostly non-book.** The claim that mosaic rhyme is the dominant construction
in rap and hip-hop comes from craft tradition and from Pat's columns and
Coursera material, not from *Essential Guide to Rhyming*. No specific rapper's
rhyme chains are reproduced here, because none appear in the book, and coining
them and attributing them to a named artist would be worse than omitting them.
If a writer wants worked rap examples, send them to the primary recordings.

What the book *does* say about the genre is narrow and usable — the g-dropping
trick from Chapter 4:

> "This trick works especially well in country and hip-hop, where `g` is
> dropped almost as a matter of principle."
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 4

with his own worked pair:

```text
sailin'  /  tail him
```

The transferable discipline — and the part that squares with Pat's method — is
that every word becomes rhyme-able once you decompose its *sound* and
reassemble a matching unit out of several words. That is exactly the move Pat
makes in Chapter 2 when `business` has no dictionary partner: the feminine
<!-- spellchecker:off -->
section under "IZ ness" is empty, so he rebuilds the word from two *masculine*
<!-- spellchecker:on -->
columns — short `i` + `z` for the stressed syllable (`fizz`, `quiz`) and short
`e` + `s` for the unstressed tail (`less`) — and gets `fizzless` / `quizless`.
The book's route to a mosaic is: fail in the obvious section, then rebuild from
a different section of the dictionary.

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

The mosaic column runs alongside the standard tiers rather than replacing
them; generate as many candidates per seed word as the search yields.
Stressed-vowel anchor identification + identity check still apply. (The book
sets no candidate count — Pat's own `business` search produced seven from the
short `i` + `z` column and eleven from short `e` + `s`.)

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
| `só-li-tà-ry` (X.X.) | double trochee | `só-lemn Mà-ry` (X.X.) | `the so-lém-ni-ty` (.X..) |

The meter scan (per [meter](meter.md)) is the gate. Mosaic that breaks
meter does not earn its place in a hot spot.

Pat's own version of this gate is the `business` filter in Chapter 2. He had a
sound-legal list — the short `e` + `s` column, printed with his own two marks on
it —

<!-- book worksheet word lists trip the spell-checker --><!-- spellchecker:off -->

```text
Bess
bless
chess
dress
fess
guess
jess
less (eureka)
mess (hmmm)
press
stress
```

<!-- spellchecker:on -->

He threw nearly all of it out on stress grounds: "Most of
these are too strong to work as the unstressed syllable in a feminine mosaic.
You need something with the same stress pattern as `busi-ness`." Try `guess`
and Pat prints two failing scansions: `his guess` marked `/ /` (both stressed,
where the target has one), "…or, even worse," `his guess` marked `˘ /` — the
stress on the tail, the exact opposite of `busi-ness`. "Both of these are
forced and again, self-consciously funny." Only `less` survives, "since it
actually could be unstressed." Sound-legal is not the same as scannable.

## Mosaic risk register

**Generated, not Pat's.** No failure-mode table appears in *Essential Guide to
Rhyming*. The rows below are this plugin's own; the only one traceable to the
book is the meter-break row, which is Pat's `busi-ness` stress filter above.
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

**Generated, not Pat's.** These two lists are the plugin's decision aid. Pat
prints no "use when" criteria for mosaic; in the book, mosaic is simply what
you reach for when the feminine section comes up empty (Chapter 2) or when a
feminine target's unstressed syllable rhymes with a pronoun (Chapters 4 and 6).

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

Per [rhyme-strategy](rhyme-strategy.md) decision matrix: pick the option
that serves emotional intent. Mosaic is one search lane among several, not a
default — and it is orthogonal to the stability tiers, since a mosaic can land
anywhere from perfect down to subtractive.

## Surfacing mosaic to the writer

The AI surfaces mosaic candidates in the standard rhyme list (per
[rhyme-generation](rhyme-generation.md) Step 8) BUT labels them as
mosaic and shows the decomposition:

<!-- phonetic vowel markings trip the spell-checker --><!-- spellchecker:off -->

```text
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

<!-- spellchecker:on -->

Each mosaic candidate gets:

- The decomposition shown
- A POS / phrase-type label
- Closure / openness signal
- Cliche-risk if any
- Register fit signal

## Examples by source type

**Generated, not Pat's.** Every table in this section is machine-generated in
the shape of Pat's constructions — none of these pairs appear in
*Essential Guide to Rhyming*. Pat's actual pairs are in the reference table
near the top of this file. Run the identity check and the meter scan on any
candidate below before using it; several are deliberately included at varying
quality so the tiering is visible.

### Common nouns

| Source | Mosaic options (generated; check identity + meter per song) |
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
- [response-filter](response-filter.md) §1 — mandatory mosaic-surface check
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
> (*Essential Guide to Rhyming* (2014), Introduction)

Mosaic rhyme works because the ear hears the SOUND, not the spelling or
the part of speech. Pat's craft applies the same identity check + tier
walk + cliche scan to multi-word units. The AI must surface this construction
or it has under-served the song.
