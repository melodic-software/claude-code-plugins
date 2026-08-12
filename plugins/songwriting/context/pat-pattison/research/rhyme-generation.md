# Rhyme Generation — Internal Discipline (Pat-Guided)

The model's internal phonetic vocabulary is broad and includes proper nouns,
pop culture references, settings, slang, and contextual words that a generic
rhyming dictionary misses. **Internal generation is primary.** External
APIs (`ai-tools.md`) supplement when vocabulary is thin or verification is
needed — they do not replace the model's craft application.

The key is to apply Pat's discipline to internal generation, NOT to skip the
discipline and trust intuition.

## Source

Synthesized across *Essential Guide to Lyric Form and Structure* (1991),
Chapter 4 (rhyme structure), *Essential Guide to Rhyming* (2014), Chapters 1-9 (rhyme types,
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

- pure vowels: ä (papa); tongue leg ă (cat), ĕ (end), ĭ (it), ē (me);
  lip leg ŭ (up), ŏ (hot), oo (foot), ū (too)
- long ā (play), long ī (cry), long ō (grow), long ū (too)
- diphthongs: oi (boy), ou (couch), ay, oy
- r-colored: ēr (ear), ār (air), ōr (door), ūr (tour)

The rhyme search is fundamentally a stressed-vowel search. Pre-vowel and
post-vowel consonants come second.

### Step 1b — Search the vowel FIELD, not the source word's own coda

Those two sentences are the instruction that failed in production. Anchoring on the
stressed vowel and then searching the source word's OWN post-vowel consonant returns
one column of the field and stops. Enumerate the field first; Steps 3, 4, 4b and 5
then LABEL what the field produced, rather than each re-running the source coda.

- The **column** is one post-vowel consonant (or cluster) on the stressed vowel —
  `et`, `il`, `isk`.
- The **field** is that same stressed vowel with the other codas the language puts
  after it. The source word's own coda is one row of the field, not the field.

Pat runs the field himself, in print. In *Essential Guide to Rhyming* (2014),
Chapter 7's complete search, keyword 6 `risk` has a Perfect Rhymes column two lines
long (`disc` / `(oops!)`) while the Imperfect column beside it crosses roughly
fifteen different codas on the one short-`i` vowel. Keyword 7 `chance` does the same
across short `a`; keyword 3 `flirt` across r-colored `ur`. The columns are printed in
full in [rhyme-worksheets.md](rhyme-worksheets.md) "The complete Chapter 7 search" —
read them there rather than reproducing them; their strategic reading is in
[rhyme-strategy.md](rhyme-strategy.md) "The full rhyme search".

**The walk ORDER below is this plugin's assembly, not a printed list.** Pat prints
two search orders and neither one is a walk across codas: Chapter 4 orders the search
WITHIN one phonetic family (perfect, then partner, then companions, then the
remaining members), and Chapter 5 orders additive rhyme by how much sound gets added
— voiced plosives, then unvoiced plosives, then unvoiced fricatives — under the
guideline "In general, the more sound you add, the less stable the rhyme becomes."
The field is Pat's; the order composes his two printed orders so the walk starts
where the ear notices least.

1. The source word's own coda — one row, logged as such.
2. That coda's phonetic relatives, via the family table in Step 4.
3. The remaining consonant groups, in Chapter 5's noticeability order — voiced
   plosives, unvoiced plosives, unvoiced fricatives — then voiced fricatives and
   nasals, then `l` and `r`, which Chapter 5 says carry the most weight.
4. Clusters on the same vowel (Chapter 4, "SYLLABLES ENDING IN MORE THAN ONE
   CONSONANT").
5. The bare open vowel — Step 4b's trigger read in reverse, i.e. subtractive.

Write each row as a coda column, the way Pat writes `ud`, `uk`, `as`, `urd`, `elt`:

<!-- spellchecker:off -->
```text
stressed vowel: ĕ (end)          source word: forget          own coda: et

et    regret   upset   duet   cassette
ed    thread   instead   bled
ek    wreck   check   speck
es    dress   confess   address
esh   fresh   refresh
est   chest   request   arrest
esk   picturesque   grotesque
ent   cement   lament
elt   felt   heartfelt   melt
```
<!-- spellchecker:on -->

No coda count is prescribed. The stopping rule is already in place: §1 of
[response-filter.md](response-filter.md) sets the ≥8-candidate floor, and Chapter 7
sets the posture — over-generate, then trim ("The list will have to be trimmed down
later").

**Writer-caught in production, 2026-08-12 (the Sofía sessions).** A search run on the
source word's own rime (`et`, and separately `il`) missed the ladder across codas on
the same vowel. The quartet `chest / dress / picturesque / forget` spans four codas
(`st` / `s` / `sk` / `t`) on one ĕ, and all four survive the Step 2 identity check
because their pre-vowel consonants (`ch` / `dr` / `r` / `g`) all differ.

Two cautions carried from elsewhere in this corpus rather than restated here. Family
assonance — which lets the walk move to a NEIGHBOURING vowel and start the field
again — is one step along a leg of the vowel triangle; use Step 5 as printed and do
not re-derive the figure. And before treating a polysyllabic candidate as a masculine
rhyme, check that its PRIMARY stress is on the syllable you are rhyming: `picturesque`
qualifies, `sunset` does not, and [rhyme-types.md](rhyme-types.md) has the trap in
Pat's own words on `lineage`.

**Datamuse cannot run this walk.** No mode of
`${CLAUDE_PLUGIN_ROOT}/context/pat-pattison/scripts/datamuse.sh` accepts a phonetic
post-vowel constraint — `pattern` (`sp`) matches SPELLING, and `near` (`rel_nry`),
`family` and `sounds` (`sl`) return opaque similarity rankings with no coda control.
The walk is internal generation only. Datamuse supplements AFTER it: confirming a
walked candidate is a real current word, adding breadth the model did not recall, and
verifying syllable counts (`syllables`). See [ai-tools.md](ai-tools.md).

### Step 2 — Apply the identity check FIRST

Before adding any candidate, run the identity check from *Essential Guide to Rhyming* (2014), Chapter 1:

- **Pre-vowel consonants MUST DIFFER.** `time/rhyme` rhymes; `time/sometime`
  is identity (both pre-vowel `t`), not rhyme.
- Suffix words (`-ation`, `-ing`, `-tion`, `-ly`, `-ness`) routinely produce
  identities that look like rhymes. Reject.

This step is where most AI-generated rhyme lists lose members. No measured
proportion is claimed — Pat gives none, and neither does this plugin.

### Step 3 — Walk the stability scale (*Essential Guide to Rhyming* (2014))

For each rhyme candidate, classify on Pat's scale:

| Tier | Definition |
|---|---|
| Perfect | identical vowel + identical post-vowel consonant + different pre-vowel |
| Family | identical vowel + post-vowel consonant from the same phonetic family + different pre-vowel |
| Additive / subtractive | identical vowel + one consonant added/removed |
| Assonance | identical vowel + different post-vowel consonant |
| Consonance | different vowel + IDENTICAL post-vowel consonant + different pre-vowel |

That order is Pat's printed chart, *Essential Guide to Rhyming* (2014),
Chapter 9, p.110 — "Scale of Rhyme Types: Most Stable to Least Stable",
running Perfect / Family / Additive-Subtractive / Assonance / Consonance
under a single axis labelled `Most Stable` at the left and `Least Stable`
at the right. Five types. Partial and weak-syllable rhyme are not on it.

**Do NOT attach a fixed use-case to a tier.** Chapter 9's whole argument is
that a tier's effect depends on *where you put it* — the same family rhyme
lightens a push in one position and softens a landing in the other. See
"Tier effect is position-conditional" below before labelling candidates.

Surface candidates per tier so the writer picks by **emotional intent**, not
by what came up first.

### Step 3a — Tier effect is position-conditional

*Essential Guide to Rhyming* (2014), Chapter 9. Before labelling a candidate,
mark which slot it is destined for. Pat's frame, p.108, on `abab`:

> The first three members,
>
> blush a / skin b / rush a
>
> …push forward. They raise our expectations, creating something akin to a
> musical dominant function, a V, which asks to be resolved to a tonic
> function, a resolution. An aba structure creates a sequence: first a, then
> b, then another a, leading us to expect another b

So the third line is the **dominant (V)** slot and the fourth is the **tonic
(I)** slot. His baseline, all-perfect, is `blush / skin / rush / sin` — and
p.109: "That's how perfect rhyme works. It delivers the maximum motion in a
rhyme scheme. In abab it delivers the hardest push in the dominant position,
and the strongest resolution in the tonic position."

Reversing which sound holds `a` reverses nothing structurally — `skin / blush
/ sin / rush` still pushes from V and lands on I: "Rush hits hard, but notice
it gets its power in part because sin has pushed so hard from its dominant
position."

Pat then walks the same four-line shape, changing only the rhyme type, keeping
the scheme stable. His printed readings — one tier, two opposite jobs.

Read the **Scheme** column first — Pat alternates between the two arrangements,
so the same word appears in V in one row and in I in another. That is his point,
not an inconsistency.

| Scheme (lines 1-4) | Dominant (V) | Tonic (I) | Pat's reading, Chapter 9 |
|---|---|---|---|
| blush / skin / rush / sin | `rush` perfect | `sin` perfect | maximum motion; hardest push, strongest resolution (p.109) |
| blush / skin / touch / sin | `touch` family | `sin` perfect | "the push at the dominant position is a little lighter (just a touch, if you will), creating a little less intensity when we land on sin. Sin-light, perhaps." The perfect tonic "slams the gates of purgatory rather than the gates of hell." (p.109) |
| skin / blush / sin / touch | `sin` perfect | `touch` family | "the landing on the family rhyme, touch, is softer and opens the gate a bit… the stable rhyme scheme has been somewhat destabilized by the rhyme type." (p.109) |
| skin / blush / drift / rush | `drift` assonance | `rush` perfect | "precious little push in dominant position, creating a bit more of an xaxa feeling"; arrival "pretty light. Nothing headlong about it." (p.111) |
| blush / skin / rush / drift | `rush` perfect | `drift` assonance | "A really hard push from the perfect rhyme blush/rush lands with a splat on the squishy surface of the assonance rhyme… The stable abab rhyme scheme has suddenly lost its ability to close the deal." (p.111) |
| skin / blush / drift / touch | `drift` assonance | `touch` family | "a pretty light and dreamy flirtation. Abab is getting less and less stable." (p.112) |
| blush / skin / touch / drift | `touch` family | `drift` assonance | "Now you're really off in dreamland, floating, floating in a misty reverie…" (p.112) |

Family rhyme is the near-substitute: "it delivers most of the power of perfect
rhyme, but not all. In either the dominant position or tonic position, the
journey has certainly been affected by changing the rhyme type, but we still
get a pretty stable feeling." (p.110)

Consonance, p.113, against family in the other slot. In dominant position
`skin / blush / dawn / touch` "barely nudges forward". In tonic position
`blush / skin / touch / dawn` — "The gate is wide open. You can feel the
instability, the desire to lean forward."

**A remote rhyme is not the same as no rhyme.** This is the generation
constraint most easily missed, and Pat makes it twice on the same page. With
consonance in the dominant slot "there is more forward pressure than with an
unrhymed first and third lines" (`skin x / blush a / breathe x / touch a`) —
"Say them both several times and you'll feel the n in action." And with
consonance in the tonic slot, against `blush a / skin x / touch a / breathe x`:

> Here, there's no sense of longing to connect back to skin, whereas in
> [`blush / skin / touch / dawn`] …you can feel dawn trembling, looking back
> to skin, feeling the pull but tearfully, reluctantly, moving on. Sad.

So never drop a rhyme when what the line wants is an unresolved one — dropping
it removes the backward pull that the remote rhyme exists to create.

One scheme-level note, p.109, on couplets:

> (In an aabb rhyme scheme, perfect rhyme creates the strongest separation
> between aa and bb because it slams the door after the first couplet,
> bringing us to a full stop before starting the motor again at b. Then it
> slams the door again at bb. That's why a steady diet of perfect rhyme
> couplets can make a song feel so long: we have to stop every two lines, then
> start the car again until we hit the next stop sign.)

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

### Step 4b — When family rhyme is not available

Do not silently drop to assonance. Pat names three triggers, verbatim,
*Essential Guide to Rhyming* (2014), Chapter 5, p.49:

> Sometimes, family rhyme won't help:
>
> 1. when words end in vowels
> 2. when your family rhyme search has not given you acceptable choices
> 3. when you're looking for a less stable rhyme type

Trigger 1 is structural and the generator must test for it first: "Family
rhymes depend on consonants after the syllables' stressed vowels. When there
are no consonants after the vowels, family rhymes aren't an option." Such words
end in an **open vowel** — every one long except `ä` as in "papa".

In all three cases the next tier is **additive / subtractive**, not assonance.
Its definitions, the search order through the consonant families, the
`free / shields` guard against over-generating on the definition alone, and the
worked `fast` subtraction are all in
[rhyme-types.md](rhyme-types.md) §"Additive Rhyme" and §"Subtractive Rhyme".
Generate against those rather than re-deriving the procedure here.

### Step 5 — Use the vowel triangle for assonance and family vowels

Pat's vowel triangle (*Essential Guide to Rhyming* (2014), Chapter 8):

- Apex: ä (papa) — most open
- Right leg (lip vowels): ä → ŭ (up) → ŏ (hot) → oo (foot) → ū (too)
- Left leg (tongue vowels): ä → ă (cat) → ĕ (end) → ĭ (it) → ē (me)

**Do not re-derive this from the EPUB text layer.** Pat prints the Vowel
Triangle as a **V with the apex `ä (papa)` at the bottom**; the text layer
hoists `ä` to the top and transposes vowels on both legs. Verified here
against the page scan (*Essential Guide to Rhyming* (2014), Chapter 8;
spine 095, figure repeats at 100/101/103; book index "Vowel Triangle,
82-83, 87, 88, 90-91"). This is load-bearing: family assonance is one step
along a leg, so a transposition changes which pairs count as adjacent.

Adjacent vowels on either leg = family assonance (smooth voice leading,
near-perfect-feel sung).

Diphthong decomposition (*Essential Guide to Rhyming* (2014), Chapter 8):

- long ā = ĕ + ē (singer holds ĕ)
- long ī = ä + ē (singer holds ä)
- long ō = ŏ + ū
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

This is why object-writing the world first (*Writing Better Lyrics* (2009),
Chapter 1; *Songwriting Without Boundaries* (2011), Challenge 1) is
prerequisite for rhyme work: object-writing generates the world's
vocabulary, which becomes the worksheet input.

### Step 6b — The final-stress Latinate/French family (writer-supplied, 2026-08-12)

**Writer-supplied observation from the Sofía sessions (2026-08-12).** It is not a
sourced claim about pop vocabulary and not a measurement of it — no proportion, share,
or count is claimed, and the members below are a starting stock, never an exhaustive
list.

The observation: a body of multisyllabic Latinate/French words is in actual pop usage
and never surfaces from a column search. Named here as the **final-stress
Latinate/French family**, because that is the phonetic property that both explains the
miss and makes the words usable:

- their PRIMARY stress falls on the final syllable, so they behave as masculine
  rhymes on that syllable — which is what Chapter 3's selection rule asks for ("Find
  mostly masculine words");
- and that final syllable's coda is usually NOT the source word's coda, so a search
  that sweeps the source column never reaches them. Step 1b's field walk does.

Starting stock, grouped by the coda that carries them:

- `esk` — picturesque, statuesque, grotesque, burlesque
- `et` — silhouette, cigarette, cassette, roulette, marionette, vignette, brunette
- `ād` — masquerade, charade, promenade, parade, serenade, escapade

The `ād` group is not a plugin invention: `charade`, `masquerade`, `parade` and
`promenade` are Pat's own printed candidates in the Chapter 3 and Chapter 7 columns
for keyword 2, `afraid` (see [rhyme-worksheets.md](rhyme-worksheets.md)). Treat the
group as the licensed pattern and the other two as the same pattern extended.

**Not a licence to reach for rare words.** The same writer, in the same session,
rejected `silt` as too literary while accepting `picturesque`. The distinguishing
property is that these words are in actual pop usage despite being multisyllabic and
Latinate — not that they are unusual. A word that is merely rare fails on register
even when it walks out of the field cleanly. The register judgement belongs to §2 of
[response-filter.md](response-filter.md) and to pass 8 of
[line-edit-rubric.md](line-edit-rubric.md), not to §1; surface the candidate with its
tier label and let the line-writing filter and the writer's ear decide.

Run each member through the Step 2 identity check and the secondary-stress caution in
Step 1b before using it.

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

Additive / subtractive (one consonant added or removed):
- (this slot is never optional — it sits between Family and Assonance on
   Pat's printed scale, and it is the tier to reach for when the source
   ends in an open vowel; see Step 4b)

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

## Why the tier label carries the emotion — Pat's worked case

*Essential Guide to Rhyming* (2014), Chapter 9, pp. 115-118, on Randy Newman's
"Feels Like Home". Of the first prechorus: "Essentially, it's common meter with
a shorter second and fourth line matching." The second prechorus repeats that
structure exactly; the rhyme type is the only variable.

First prechorus, the pair `long / done` (italics as printed, p.116):

> Does *long/done* rhyme? Well, I don't really care what you call it, but it
> does have some sonic connection:
>
> *Ng* and *n* are members of the same family, the nasals. So *long/done*
> amounts to a *family/consonance* rhyme, about as far afield as you can go and
> still give a hint of a sonic resemblance. It probably wouldn't be audible at
> all without the help of common meter, but it sure opens the gate at the end
> of the section, creating instability rather than closure.
>
> And what's the *emotion* that the rhyme type creates? Something like *longing
> and uncertainty*, which, of course, is exactly what the lyric itself is
> saying. Pretty cool.

Second prechorus, the pair `touch / much`: "Perfect rhyme. And, boy, does the
gate ever slam shut. This is the essence of stability—the same thing, of
course, that the lyric is addressing." (p.117)

> The rhyme types alone are responsible for the difference in feeling between
> the first and second prechoruses—the family/consonance rhyme, long/done,
> supporting (maybe even creating) the unstable feeling in the first prechorus,
> and the perfect rhyme, touch/much, supporting (maybe even creating) the
> stable feeling in the second.

Pat then runs the experiment both ways. In the second prechorus he swaps the
`touch` of the shorter second line for a non-rhyming word, so the closing
fourth line — unchanged — is left with nothing to resolve against (p.117):

> The last line, which seemed like such an emotional line, has lost a lot of
> its feeling. It seems less glorious, less heartfelt. What seemed like such a
> sensational line has turned ordinary. The meaning hasn't really changed. But
> the motion, and thus the e-motion, has transformed dramatically.

In the first prechorus he goes the other way, rewriting the closing fourth line
so that `long` is answered by a perfect rhyme instead of by `done` (p.118):

> Again, the meaning is essentially the same, but now we hear a tribute to the
> power of love, a stable feeling created, again, simply by the rhyme type. It
> not only transforms the emotion of the section, but the color of the entire
> first sequence of verse/prechorus/chorus. […] Rather than moving
> unstable/unstable/stable in the first sequence, we're moving
> unstable/stable/stable, and the last part of the song feels more like it
> repeats the same ideas rather than growing.

**The generation lesson.** A rhyme-type choice at one slot is not local. It
sets the stability of the section, and the section's stability sets whether the
song's later sequence reads as growth or as repetition. Label candidates with
that reach in view, not just with how the pair sounds.

The same book's verse pair makes the structural half of the point: verse 1
"lacks rhyme in the fourth and eighth lines, creating instability and opening
the gate into the prechorus. The second verse does the opposite" (p.118).

## Worksheet generation (*Essential Guide to Rhyming* (2014), Chapter 3 + Chapter 7)

For longer rhyme work — title development, theme exploration — build the
worksheet. Pat's three steps, verbatim, *Essential Guide to Rhyming* (2014),
Chapter 3, p.19:

> The trick is to look for rhymes *before* you start to write. It is not as
> hard as it sounds.
>
> 1. Focus your lyric idea as clearly as you can.
> 2. Make a list of words that fit your idea.
> 3. Look up those words in your rhyming dictionary, and make lists of rhyme
>    words that fit your idea.

Step 2's selection rules are **phonetic, not thematic**. Pat states two, and
only two (p.20): "Find mostly masculine words. Pick words with different vowel
sounds." His own running list runs to eleven seeds, not a range. Do not sort
seeds into emotion / action / relationship / conflict buckets — that is not
his instruction.

Step 3 in Chapter 3 is a **perfect-rhyme** search only; the rule for keeping a
rhyme is one sentence, "Write down only rhyme words that fit with your idea."
(p.21). Expanding the same worksheet across the whole stability scale is
Chapter 7's job, not Chapter 3's.

Mechanics, seeds, the completed "RISKY BUSINESS" columns and Pat's comments on
his own search live in [rhyme-worksheets.md](rhyme-worksheets.md); the full
Chapter 7 expansion search lives in [rhyme-strategy.md](rhyme-strategy.md).
Generate against those, do not re-derive here.

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
