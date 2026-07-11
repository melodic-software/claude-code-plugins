# Rhyme Generation — Internal Discipline (Pat-Guided)

The model's internal phonetic vocabulary is broad and includes proper nouns,
pop culture references, settings, slang, and contextual words that a generic
rhyming dictionary misses. **Internal generation is primary.** External
APIs (`ai-tools.md`) supplement when vocabulary is thin or verification is
needed — they do not replace the model's craft application.

The key is to apply Pat's discipline to internal generation, NOT to skip the
discipline and trust intuition.

## Source

Synthesized across Books 1 Chapter 4 (rhyme structure), 4 Chapters 1-9 (rhyme types,
phonetic families, worksheets, sonic bonding), and `rhyme-types.md` +
`rhyme-strategy.md` + `rhyme-worksheets.md` + `rhyme-fundamentals.md`.

## When this file applies

Any user request for:

- "rhymes for X"
- "what rhymes with X"
- "find non-cliche rhymes"
- "near rhymes / slant rhymes"
- "family rhymes"
- worksheet generation for a title or seed word
- rhyme position decisions inside a draft

## The internal generation discipline

Run these steps in order. Skipping a step usually means the rhyme list will
disappoint.

### Step 1 — Anchor the stressed vowel

Pat's worksheet starts with the stressed vowel of the rhyme word. Identify
it exactly:

- short ä (papa), short ŭ (up), short ĕ (end), short ĭ (it), long ē (me)
- long ā (play), long ī (cry), long ō (grow), long ū (too)
- diphthongs: oi (boy), ou (couch), ay, oy
- r-colored: ēr (ear), ār (air), ōr (door), ūr (tour)

The rhyme search is fundamentally a stressed-vowel search. Pre-vowel and
post-vowel consonants come second.

### Step 2 — Apply the identity check FIRST

Before adding any candidate, run the identity check from *Essential Guide to Rhyming* (2014), Chapter 1:

- **Pre-vowel consonants MUST DIFFER.** `time/rhyme` rhymes; `time/sometime`
  is identity (both pre-vowel `t`), not rhyme.
- Suffix words (`-ation`, `-ing`, `-tion`, `-ly`, `-ness`) routinely produce
  identities that look like rhymes. Reject.

This step alone removes ~30% of typical AI-generated rhyme lists.

### Step 3 — Walk the stability scale (*Essential Guide to Rhyming* (2014))

For each rhyme candidate, classify on Pat's scale:

| Tier | Definition | Strong fit for |
|---|---|---|
| Fully resolved / perfect | identical vowel + identical post-vowel consonant + different pre-vowel | full closure, chorus-ending stop, central section landing |
| Family | identical vowel + RELATED post-vowel consonant + different pre-vowel | almost-closure, expressive softening, verse texture |
| Additive / subtractive | identical vowel + one consonant added/removed | open-ended forward motion, suspension |
| Assonance | identical vowel + different post-vowel consonant | high openness, low closure |
| Consonance | different vowel + similar post-vowel consonant | strategic deceleration, ironic mismatch |

Surface candidates per tier so the writer picks by **emotional intent**, not
by what came up first.

### Step 3b — MOSAIC tier (mandatory surface)

After walking the single-word stability scale, generate the MOSAIC tier
per [mosaic-rhyme.md](mosaic-rhyme.md). Mosaic = multi-word combos that
rhyme with the source by sound, crossing parts of speech, including
proper nouns and slang.

Pat's masculine / feminine / mosaic taxonomy is named explicitly in
*Essential Guide to Rhyming* (2014), Chapter 1. The AI's default is
single-word-rhyme — mosaic must be ACTIVELY generated, not assumed.

For each source word:

- **Single-side mosaic** — source word ↔ multi-word combo (`Texas` ↔
  `wrecks us`; `silence` ↔ `find us`; `morning` ↔ `for me`)
- **Both-side mosaic** — multi-word ↔ multi-word (`tell us` ↔ `jealous`;
  `up against` ↔ `whiff incense`)
- **Cross-part-of-speech** — noun ↔ verb+pronoun, adjective ↔
  imperative-phrase, abstract ↔ concrete-action-phrase
- **Proper-noun mosaic** — names, places, brands, eras (when the song's
  world established them)
- **Slang / contraction stack** — `gonna get a`, `let me have a`,
  `should've been a`

Apply identity check across the multi-word boundary. `Texas / text us` =
identity (pre-vowel `t` repeats); REJECT. `Texas / wrecks us` = rhyme
(pre-vowel `t` ↔ `r`); ACCEPT.

Apply meter check: mosaic must preserve the source's stress paradigm.
`Téx-as` (X.) pairs with `wrécks-us` (X.); not with `whatever wrecks
us` (..X.) unless meter accommodates.

Surface ≥3 mosaic candidates per rhyme task. More when source is a
proper noun, polysyllabic abstraction, or rare-consonant-cluster word
(these are mosaic-territory by default).

### Step 4 — Use the phonetic family map for family rhymes

Pat's three horizontal families (*Essential Guide to Rhyming* (2014), Chapter 4):

- **Plosives** — b/d/g (voiced), p/t/k (unvoiced). Partners (same mouth
  position) are closer than companions (same voicing). b↔p, d↔t, g↔k as
  partners.
- **Fricatives** — v/TH/z/zh/j (voiced), f/th/s/sh/ch (unvoiced).
  Companions closer than partners — fricatives have duration, voicing is
  more audible over sustained airflow, mouth positions are already close.
- **Nasals** — m/n/ng. All voiced; companions only.

Family rhyme search order for post-vowel consonant:

1. Perfect (same consonant)
2. Family partner OR companion (per family rules above)
3. Remaining family members
4. Multi-consonant cluster preservation

This generates legitimate family rhymes the model can produce directly from
its phonetic knowledge — no external lookup needed.

### Step 5 — Use the vowel triangle for assonance and family vowels

Pat's vowel triangle (*Essential Guide to Rhyming* (2014), Chapter 8):

- Apex: ä (papa) — most open
- Right leg (lip vowels): ä → ŏ (hot) → ū (too) → oo (foot)
- Left leg (tongue vowels): ä → ŭ (up) → ĕ (end) → ĭ (it) → ē (me)

Adjacent vowels on either leg = family assonance (smooth voice leading,
near-perfect-feel sung).

Diphthong decomposition (*Essential Guide to Rhyming* (2014), Chapter 8):

- long ā = ĕ + ē (singer holds ĕ)
- long ī = ä + ē (singer holds ä)
- long ō = ŏ + ū (singer holds ŏ)
- oi = ŏ + ē
- ou = ä + ū

Hidden assonance: two words sharing one component of a diphthong feel
connected to the listener.

### Step 6 — Generate from the song's developed world

This is the model's strongest territory and where Datamuse is weakest. The
song establishes a world: setting, time, character, era, dialect, mood,
genre. Pull rhyme candidates from THAT world before pulling from a generic
list.

If the song is set in a 1970s Tennessee bar, the rhyme candidates should
include words from that world (proper nouns, brand names, regional terms,
era-specific objects) — not just dictionary entries. The world's vocabulary
is the writer's primary rhyme inventory.

This is why object-writing the world first (Books 2 Chapter 1, 3 Challenge 1) is
prerequisite for rhyme work: object-writing generates the world's
vocabulary, which becomes the worksheet input.

### Step 7 — Run cliche scan on every candidate pair

For each (rhyme-position-word, candidate) pair, flag cliche risk:

- Predictable perfect-rhyme pairs (moon/June, fire/desire, heart/apart, sky/cry, night/light, tears/years)
- Cliche metaphor families (storm-anger, fire-passion, darkness-sadness, prison-love, drown-in-love)
- Generic abstractions in rhyme positions (love, soul, heart, dreams, alone)

A "friendly cliche" (*Writing Better Lyrics* (2009), Chapter 5) — one earned by reframing context — is
fine. A naked cliche in a hot spot is not.

### Step 8 — Surface candidates with labels

Don't pick one. Return 8-15 candidates labeled per tier + cliche risk +
syllable match + line-context fit. Let the writer choose by emotional
intent, not by your top guess.

Format:

```
Stressed vowel: long-O (as in "lonely")
Source stress: trochee (X.)

Perfect (fully resolved, single-word):
- only           — REJECT, identity risk (no pre-vowel difference)
- holy           — perfect; HIGH cliche pair with "lonely"
- slowly         — perfect; MED cliche pair

Family (post-vowel consonant family-related):
- (limited single-word options for -L-Y ending; mosaic territory)

Assonance (vowel-only match):
- broken         — long-O, different post-vowel; STRONG for forward motion
- woven          — long-O, different post-vowel; STRONG
- soaking        — long-O, voice-leading well to next vowel

Consonance (post-vowel-only match):
- (rare for this source; consider only if a specific echo is wanted)

Mosaic (multi-word, cross-POS, ≥3 always):
- only me        — adverb + pronoun; closure-soft; REJECT (identity)
- show me        — verb + pronoun; openness; clean rhyme; STRONG
- told me        — verb + pronoun; closure; pulls past tense
- hold me        — verb + pronoun; closure-warm; STRONG for embrace theme
- below me       — preposition + pronoun; spatial; world-fit if applicable
- old story      — adj + noun; closure-with-history
- own glory      — pronoun + noun; mosaic-with-internal-rhyme; ironic register

From the song's world: [if context established]
- [proper nouns, setting words, era-specific words sharing -ō- vowel]
- e.g., "the Moonlight" / "the old highway" / "Joplin" if the song goes there
```

## Worksheet generation (*Essential Guide to Rhyming* (2014), Chapter 3 + Chapter 7)

For longer rhyme work — title development, theme exploration — generate the
three-stage worksheet:

1. **Stage 1 — Focus.** Distill the song's central idea to one paragraph.
2. **Stage 2 — Idea words.** Extract 8-12 seed words spanning emotion,
   action, image, relationship, conflict.
3. **Stage 3 — Rhyme search.** For each seed word, generate all five tiers
   (perfect / family / additive-subtractive / assonance / consonance) plus
   world-vocabulary candidates.

The worksheet externalizes the inward search and lets the writer choose
deliberately rather than settling for the first phrase that came to mind.

## When to fall back to external data

The model's internal vocabulary IS strong for:

- common words, proper nouns, pop culture, settings, eras
- phonetic family relationships
- vowel categorization
- stability scale application
- cliche detection

The model is weaker / external lookup helps when:

- the writer needs a HIGH volume of candidates (50+) for brainstorming
- syllable counting on rare polysyllabic words (verify with Datamuse `syllables`)
- semantic-field mining for metaphor that requires statistical word
  association (`datamuse trg <word>` returns words statistically near in
  text — broader than the model's tight associations)
- verification that a candidate is real / current usage

Route to `ai-tools.md` for the supplement, but **always with Pat's framing
applied to the output**. Datamuse returns words; the model applies tier,
identity check, cliche scan, world fit.

## Failure modes (and recovery)

| Failure | Recovery |
|---|---|
| Model proposes identities as rhymes | re-run identity check on each candidate |
| Model surfaces only cliche pairs | broaden to family / assonance tiers; pull from song's world |
| Model picks one rhyme | reject; surface 8-15 candidates with labels |
| Model invents non-words | discard; cite only real words; use Datamuse to verify if needed |
| Model rhymes from generic vocabulary | re-anchor in the song's established setting / character / era |
| Model treats syllable count as guess | verify on polysyllabic words via `datamuse syllables` |
| **Model never surfaces mosaic** | force per Step 3b — ≥3 mosaic candidates per task, cross-POS, proper-noun if world allows |
| **Model defaults to noun-noun, verb-verb** | mosaic breaks the part-of-speech mirror; reject single-POS-only lists |
| Mosaic-identity slip | re-run identity across word boundary (`Texas / text us` = identity, REJECT) |
| Mosaic breaks meter | re-scan against source stress paradigm; trim or replace |

## Cross-references

- `rhyme-fundamentals.md` — identity-vs-rhyme check origin
- `rhyme-types.md` — full stability scale + family taxonomy
- `mosaic-rhyme.md` — multi-word cross-POS tier (Step 3b)
- `rhyme-strategy.md` — decision matrix for picking tier by emotional intent
- `rhyme-worksheets.md` — three-stage worksheet mechanics
- `rhyme-sonic-bonding.md` — internal rhyme, vowel triangle, diphthong decomposition
- `ai-tools.md` — Datamuse supplement for verification and high-volume mining
- `cliche.md` — cliche taxonomy
- `object-writing.md` — generating the song's world vocabulary
- `response-filter.md` §1 — pre-flight gate; mandates mosaic tier surface
