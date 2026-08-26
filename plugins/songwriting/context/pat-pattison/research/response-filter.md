# AI Response Filter — Pre-Flight Gate for Every Output

## Contents

- [Stance: Tools, Not Rules — applied to the AI itself](#stance-tools-not-rules--applied-to-the-ai-itself)
- [How to use this file](#how-to-use-this-file)
- [§1 Rhyme suggestion filter](#1-rhyme-suggestion-filter)
- [§2 Line-writing filter](#2-line-writing-filter)
- [§3 Critique filter](#3-critique-filter)
- [§4 Coaching posture filter](#4-coaching-posture-filter)
- [§5 Title + hook filter](#5-title--hook-filter)
- [§6 Form filter](#6-form-filter)
- [§7 Image filter (object writing + metaphor)](#7-image-filter-object-writing--metaphor)
- [§8 Pre-lock filter](#8-pre-lock-filter)
- [Cross-section drift checks (run periodically across a response)](#cross-section-drift-checks-run-periodically-across-a-response)
- [Filter posture — quick reference](#filter-posture--quick-reference)
- [Cross-references](#cross-references)
- [Recheck triggers (when this filter needs revision)](#recheck-triggers-when-this-filter-needs-revision)

**This file is mandatory.** When any `/songwriting` craft skill is active — explicitly or
auto-routed — every AI response that suggests rhymes, writes a line, rewrites
a lyric, critiques a draft, or coaches process MUST pass through the
applicable section below before emission.

The filter exists because generic LLM defaults — perfect rhymes, predictable
end-lines, abstract telling, cliche imagery, single-winner picks — directly
violate Pat Pattison's craft. The filter activates the discipline already
captured in the other context files. It is the gate, not new craft.

## Stance: Tools, Not Rules — applied to the AI itself

> "There are no rules, only tools."
> — Pat Pattison, *Writing Better Lyrics* (2009), Chapter 18

The filter is a tool the AI uses to check its own work. The AI may skip a box
when justified — but a skip must be NAMED. Silent skips are not OK.

When the AI applies the filter and finds nothing applicable, it names the
no-op (aloud or in reasoning): *"Filter scan: no rhyme position, no abstract
telling, no hot-spot exposure — clear to emit."* Naming the no-op proves the
gate ran.

## How to use this file

Three entry points:

1. **Before emitting any lyric / rhyme / critique** — run the applicable
   pre-flight section below
2. **Mid-response, when the AI catches itself drifting** — re-check the
   relevant section, name the slip, correct
3. **At session start when the skill is invoked** — confirm filter is active
   for downstream outputs

The filter sections are organized by WHAT the AI is about to output:

| Output type | Apply section |
|---|---|
| Rhyme list (the writer asked for rhymes) | §1 Rhyme suggestion filter |
| Line rewrite / new line / variation | §2 Line-writing filter |
| Candidate lyric line about to be SHOWN to the writer | §2, cycled inside [line-edit-rubric.md](line-edit-rubric.md) |
| Critique / diagnosis of an existing lyric | §3 Critique filter |
| Scansion verdict, stability call, phrasing judgement | §3 Critique filter |
| Coaching / step-by-step guidance | §4 Coaching posture filter |
| Title generation / hook placement | §5 Title + hook filter |
| Form / song-shape recommendation | §6 Form filter |
| Object writing / metaphor generation | §7 Image filter |
| Pre-lock audit assistance | §8 Pre-lock filter |

Run only the applicable sections. Don't run all eight every time — the gate
must be fast or the AI will skip it under load.

## §1 Rhyme suggestion filter

**Triggers:** writer asks for "rhymes for X", "near rhymes", "family rhymes",
"alternatives to <rhyme word>", "what else rhymes with this", or AI is about
to propose a rhyme partner anywhere in output.

**Reference:** [rhyme-generation.md](rhyme-generation.md),
[rhyme-types.md](rhyme-types.md),
[rhyme-fundamentals.md](rhyme-fundamentals.md).

**Pre-flight checklist — every box NAMED out loud (✓ pass / ✗ fail+fix /
skip+reason):**

- [ ] **Stressed vowel anchored** before any candidate listed
- [ ] **Vowel FIELD walked, not just the source word's coda** — the source word's
      own post-vowel consonant is ONE row of the field. Walk the other coda
      columns on the same stressed vowel per
      [rhyme-generation.md](rhyme-generation.md) Step 1b BEFORE listing
      candidates. Anchoring the vowel and then searching the source's own rime is
      what this box used to permit, and it shipped a column sweep in production
      (2026-08-12). Pat runs the walk himself in *Essential Guide to Rhyming*
      (2014), Chapter 7: keyword `risk`'s Perfect Rhymes column is two lines
      (`disc` / `(oops!)`) while the Imperfect column beside it crosses roughly
      fifteen codas on the one vowel
- [ ] **Identity check** on every candidate — pre-vowel consonants DIFFER
      from the source word (e.g., `time / sometime` = identity, REJECTED;
      `time / rhyme` = rhyme, accepted). Identity check applies ACROSS
      multi-word boundaries for mosaic candidates too (`Texas / text us`
      = identity-in-disguise, REJECTED; `Texas / wrecks us` = rhyme).
- [ ] **No suffix-driven identity** sneaking through (`-ation`, `-ing`,
      `-tion`, `-ly`, `-ness` chains routinely produce identities)
- [ ] **≥4 stability tiers surfaced** — not all perfect. Pat's printed
      "Scale of Rhyme Types: Most Stable to Least Stable" runs, in order:
      Perfect Rhyme → Family Rhyme → Additive/Subtractive Rhyme →
      Assonance Rhyme → Consonance Rhyme (*Essential Guide to Rhyming*
      (2014), Chapter 5, chapter-opening scale)
- [ ] **MOSAIC tier MANDATORY** — ≥3 mosaic candidates surfaced per
      [mosaic-rhyme.md](mosaic-rhyme.md), regardless of source word.
      Cross-part-of-speech (verb+pronoun, adjective+noun, imperative phrase,
      contraction stack) included. Proper-noun mosaic considered when
      the song's world allows. The AI's default is single-word-rhyme; the
      filter forces mosaic onto the table.
- [ ] **Additive/subtractive search runs in Pat's noticeability order**
      when the tier is reached — voiced plosives, then unvoiced plosives,
      then unvoiced fricatives. His worked search on "free" goes
      +b ("not much there"), +d, +p, +t, +k, then +f, then +s. The
      governing guideline is printed as: "In general, the more sound you
      add, the less stable the rhyme becomes. The less sound you add, the
      more stable the rhyme becomes, and you're closer to a perfect rhyme
      substitute." Fricatives add more sound than plosives; other than
      l and r, nasals add the most (*Essential Guide to Rhyming* (2014),
      Chapter 5)
- [ ] **Masculine / feminine / mosaic** taxonomy taught (per
      *Essential Guide to Rhyming* (2014), Chapter 1) — at least one
      feminine (2-syllable) candidate AND at least one mosaic candidate
      where source allows
- [ ] **≥8 candidates total** with per-tier labels (Pat surfaces options,
      doesn't pick a winner) — typically 8-15 across tiers
- [ ] **Cliche-pair scan run** — flag (`moon/June`, `fire/desire`,
      `heart/apart`, `sky/cry`, `night/light`, `tears/years`,
      `love/above`, `kiss/bliss`, `dance/romance`, `lonely/only`,
      `dreams/seems`, `forever/together`, `arms/charms`) — REFRAME or REJECT
- [ ] **Song's developed world pulled from** — if the song has setting / era
      / character / proper nouns, ≥3 candidates come from THAT vocabulary,
      not a generic dictionary. Proper-noun mosaic actively considered.
- [ ] **Syllable match flagged per candidate** when the rhyme position
      demands a specific stress count (mosaic must preserve source meter)
- [ ] **NO single winner imposed** — writer picks by emotional intent
- [ ] **Sing-check noted** — the AI cannot sing; the WRITER must sing-check.
      Not optional politeness: Pat makes singing the test that settles an
      additive rhyme, twice in *Essential Guide to Rhyming* (2014), Chapter 5
      alone (see anchor quotes below).
      Chapter 4 gives the reason — "Since lyrics are sung, vowel sounds are
      promoted and consonant sounds are demoted. If you take the time to
      sing the family rhymes, they will not trouble your sensibilities."
      (*Essential Guide to Rhyming* (2014), Chapter 4)

**Fail signature 1 — single-word default:** if the AI's about-to-emit
rhyme list reads like [`rose`, `chose`, `pose`, `nose`, `goes`, `knows`,
`shows`] — all perfect, all single-word, all generic, all same part of
speech, no family alternates, NO MOSAIC — the filter has failed. STOP.
Rebuild with the checklist applied. The mosaic tier alone usually adds
5-15 candidates that change the song's surface entirely (`those who chose`,
`dispose`, `hold those`, `behold us`, etc.).

**Fail signature 2 — phrase-containing-source-word as fake mosaic:** if
the AI's "mosaic" list for source `around` reads as [`sleep around`,
`push me around`, `let me down`, `kicked around`, `messed around`,
`pass it around`] — every entry REUSES the source word with a prefix —
that's IDENTITY-WITH-PREFIX, NOT mosaic. True mosaic decomposes the
source SOUND (stressed vowel + post-vowel consonants) and rebuilds with
a multi-word unit whose syllables match WITHOUT using the source word.
For `around` /əˈraʊnd/ → true mosaic = `the sound`, `the ground`, `they
found`, `renowned`, `a hound`, `wear the crown` (family) — multi-word
units whose stressed syllable matches /aʊnd/ via different lexical
content. The LLM default is search-and-find-phrases-with-source-word;
the filter must catch this. See [mosaic-rhyme.md](mosaic-rhyme.md)
"Mosaic risk register" → "Phrase-containing-source-word default" row.

**Fail signature 3 — column sweep dressed as a tier walk:** the about-to-emit list
for source `forget` reads [`regret` perfect, `duet` perfect, `cassette` perfect,
`thread` family, `instead` family, `bled` family, `they get it` mosaic, `let it set`
mosaic]. Tier-labeled, mosaic present, ≥8 candidates, no identity, no cliche pair —
every box above is nameable as a pass, and signatures 1 and 2 both clear it. It is
still a COLUMN SWEEP: every entry sits on `et` or on `et`'s immediate phonetic
relative `ed`, and the rest of the ĕ field was never searched. The tell is what is
ABSENT, not what is present — `es` (`dress`, `confess`), `est` (`chest`, `arrest`),
`esk` (`picturesque`, `grotesque`), `elt` (`felt`, `melt`) are all live rows on the
same stressed vowel. Writer-caught in production, 2026-08-12, on this exact vowel:
`chest / dress / picturesque / forget` spans four codas (`st` / `s` / `sk` / `t`) on
one ĕ, and all four pass the identity check because their pre-vowel consonants
(`ch` / `dr` / `r` / `g`) differ. STOP and run the walk in
[rhyme-generation.md](rhyme-generation.md) Step 1b. This is a SEARCH-SPACE failure,
not a rhyme-type failure — the tier labels can all be correct and the field still
unsearched.

**Anchor quote:**

> "Never stop listening. If your ear says a sound is wrong, find another
> rhyme. Trust your ears. (But be sure to sing your rhymes when you check.)"
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 5

And again two pages later, closing the l/r additive lists:

> "Again, sing them. Trust your ears."
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 5

## §2 Line-writing filter

**Triggers:** writer asks for "a new line", "rewrite this line", "alternative
phrasing", "say this differently", "variations", or AI is about to emit
any prose lyric line.

**Reference:** [object-writing.md](object-writing.md),
[cliche.md](cliche.md), [phrasing.md](phrasing.md), [meter.md](meter.md),
[hook.md](hook.md), [variations.md](variations.md),
[voiceprint.md](voiceprint.md).

**This Reference line is a load list, not a bibliography.** §2 has not been run
until these files have been READ this session. Naming the boxes below while
`meter.md` and `phrasing.md` were never opened attests to the filter instead of
applying it, and that attestation is what let the production failures through
(2026-08-12): the miscounted stresses and the plain description labeled a metaphor
both came out of a §2 that was named, not loaded.

**When the output is a candidate line about to be SHOWN to the writer, this
section's boxes are cycled inside pass 6 of
[line-edit-rubric.md](line-edit-rubric.md) — not run twice.** That file is the
pre-emission cycle; §2 remains the OWNER of the boxes below and is what its pass 6
loads. For every other §2 trigger — a line inside a critique, a rewritten fragment
in prose — run §2 here, as printed. A full pre-emission cycle cannot live inline in
a gate held to the `## Recheck triggers` ~10s budget at the bottom of this file;
that is why it is a separate file rather than more of this section.

**Pre-flight checklist:**

- [ ] **Sense-bound** — ≥1 of the seven senses present (sight, hearing,
      smell, taste, touch, organic, kinesthetic). Pure abstraction = FAIL
- [ ] **Show before tell** — if the line names an emotion / lesson / topic,
      a Rusty's-Collar concrete image precedes or accompanies it
- [ ] **Specific noun** over generic label (`the bar` → `the Moonlight`;
      `the place` → which place; `the love` → whose love)
- [ ] **Strong verb** doing real work (NOT `to be` + adjective when an
      action verb would land harder)
- [ ] **No abstraction in a hot spot** (line 1 of section, last line of
      section, last word before a rhyme position)
- [ ] **Hot-spot phrase rule** — within a phrase: 2nd-most-important word at
      the beginning, most-important word at the end (or first/last per
      front-heavy/back-heavy choice — `front-heavy` / `back-heavy` are **Pat's
      own terms**, coined in his patpattison.com "The Art of Phrasing" column
      rather than in any of the four books, so cite the column and never a
      chapter; see [book-references.md](book-references.md))
- [ ] **Stress map** — every stressed syllable lands on a strong beat (no
      greedy spots — unstressed forced to a downbeat, or stressed forced
      to a weak beat)
- [ ] **Compound-word stress** — primary stress on the first syllable
      (`hómework`, `súnrise`); naming this prevents misalignment
- [ ] **"into" rule** — `ínto` not `intó` (per *Without Boundaries* (2011),
      Challenge 4)
- [ ] **Cliche scan** — no stale phrase (`broken heart`, `lonely night`,
      `fire of love`, `walking on sunshine`, `dance in the rain`,
      `chasing dreams`, `against the wind`, `the writing on the wall`,
      `to the moon and back`), no cliche metaphor family unreframed
      (`storm-anger`, `fire-passion`, `darkness-sadness`, `prison-love`,
      `drown-in-love`, `journey-life`, `wings-freedom`,
      `road-life-path`)
- [ ] **Friendly cliche test** — if a cliche is used: is it reframed by
      context so it earns its place? If no → REWRITE
- [ ] **Rewrite stays in the common stock** — a cliche flag is answered by
      reframing (the box above), not by reaching for a rarer word. Order of
      generation: [line-brainstorm.md](line-brainstorm.md) "Discipline" —
      common stock first, reframe second. Whether a candidate is SAYABLE at
      all is a separate check with its own grounding (pass 8 of
      [line-edit-rubric.md](line-edit-rubric.md)); it is NOT an extension of
      the `Tone-of-voice` box below, which is plugin shorthand with zero
      corpus hits. Writer-derived, Sofía sessions (2026-08-12)
- [ ] **Identity ≠ rhyme** if line sits in a rhyme position — pre-vowel
      consonants on the rhyme word DIFFER from any prior rhyme partner
- [ ] **Pronoun consistent** with section's established speaker / audience
- [ ] **Camera distance** matches section role (close-up for verse intimacy,
      middle for narrative, long-shot for chorus universality — or
      deliberate hybrid)
- [ ] **Tone-of-voice** stable — same speaker, same emotional register as
      the section's other lines (`tone of voice` is 0 hits across the four books
      and has not been located in a Pat column either — treat as plugin
      shorthand; see [book-references.md](book-references.md))
- [ ] **Vowel awareness** — the line's stressed vowels chosen, not
      defaulted; bright vowels (long-ē, long-ā) feel sharp; dark vowels
      (long-ō, long-ū) feel weighted
- [ ] **Unintended implication** — read the line as a stranger with no
      access to the writer's intent, and NAME what it implies about each
      character: their motive, their status, their history, their
      relationship. If any implication contradicts the song's premise,
      REWRITE. A line can pass every box above and still assign a
      character a motive the writer never chose.
- [ ] **Nothing without its purpose** — every element the line introduces
      (an object, a second character, a place, a time marker) does a job
      the song needs. Pat invokes Ibsen's rule about the gun in Act I:
      have a reason for each element, and no duplication of function
      (*Writing Better Lyrics* (2009), Chapter 10). An unused element is
      not neutral — the listener will assign it meaning.

**Fail signature 1 — generic abstraction:** about-to-emit line like
*"My broken heart is lonely in the dark, waiting for your love to make me
whole"* — every box fails: abstract telling, three cliches, generic nouns,
no senses, weak verbs. STOP. Rebuild from a concrete sense-bound image.

**Fail signature 2 — clean line, wrong implication:** a line like *"she
watched me from the window sill"* passes sense-bound, specific noun, strong
verb, no cliche, and consistent POV — and still reads as surveillance,
casting a chance-encounter character as a stalker or a thief sizing up a
mark. The premise is destroyed by a line with no defective box.

Why this box is not optional: Chapter 1's account of why sense-bound
language works is that the listener fills the writer's words with their OWN
sense memories and associations. That mechanism is what makes showing
powerful, and it is not selective — the listener supplies implication the
writer never placed there. Specificity increases the pull, so a MORE
concrete line carries MORE unintended implication, not less. The check runs
after the other §2 boxes pass, precisely because passing them is what makes
the risk live.

**Anchor quote:**

> "Songs should be universal, but don't mistake universal for generic.
> Sense-bound is universal."
> — Pat Pattison, *Writing Better Lyrics* (2009), Chapter 5

## §3 Critique filter

**Triggers:** writer asks for "review", "diagnose", "what's wrong with this",
"honest feedback", "Pat would say what", "scan this line", "is this section
stable", or AI is about to deliver findings on a draft — including a
scansion verdict, a stability call, a phrasing judgement, a motion diagnosis,
or a closure call.

**Reference:** [demo-review.md](demo-review.md),
[audit-checklist.md](audit-checklist.md),
[five-compositional-elements.md](five-compositional-elements.md),
[stable-unstable-meta.md](stable-unstable-meta.md), [meter.md](meter.md),
[prosody.md](prosody.md).

**Pre-flight checklist:**

- [ ] **Section types identified** — verse / chorus / bridge / refrain /
      transitional bridge — auditing a refrain like a chorus is the
      wrong test
- [ ] **Read aloud once** before analysis — first pass is sensation, not
      diagnosis (note: writer reads; AI flags this as a step)
- [ ] **Five Compositional Elements counted** per section (lines, line
      lengths, rhyme scheme, rhyme types, rhythm)
- [ ] **Line length counted in STRESSES** — every "longer", "shorter",
      "matched", or "balanced" claim is a count of stressed syllables. A
      raw-syllable count answers a different question and invents symmetry
      that is not there. No stress map marked = no length claim made
- [ ] **Spotlight carries its content** — for each position the structure
      marks (a shortened or lengthened line, a rhyme landing where none was
      predicted, a delayed payoff, a section outrunning the established bar
      count), NAME the content sitting there. A marked position holding
      filler is a finding, not a flourish; a spotlight turned on to be cute
      is a fail (*Writing Better Lyrics* (2009), Chapters 14-15). This box
      reads a draft whose marks already exist; when the output is instead a
      CANDIDATE line about to be shown for a slot whose brightness is already
      known, that check is pass 10 of
      [line-edit-rubric.md](line-edit-rubric.md), not a re-run of this box
- [ ] **Line length ruled out before a rhyme prescription** — when a finding
      about a section's motion is about to prescribe a rhyme change, the
      arrangement of LINE LENGTHS is checked first, because line length moves a
      section harder than rhyme does. This orders those two against each other
      only; against rhythm or line count the dominant-problem rule above still
      decides (*Writing Better Lyrics* (2009), Chapter 19)
- [ ] **Closure named against the ear's expectation** — calling a closure
      deceptive requires naming the prediction the section actually built;
      calling one unexpected requires that the ear predicted nothing. Deceptive
      closure buys the brightest spotlight, so it inherits the spotlight box
      above (*Writing Better Lyrics* (2009), Chapter 19)
- [ ] **Stable/unstable scan** across lyric (and melody if known)
- [ ] **Hot-spot audit** — where does the title sit? line 1 of each section?
      last line?
- [ ] **ONE dominant problem named** — not ten. If multiple, name the
      upstream one (title doesn't fit form > form doesn't fit emotion >
      verse 2 travelogues > line 4 is generic)
- [ ] **Upstream-first** — if title is wrong, fixing line-level rhymes
      won't help; name the upstream issue
- [ ] **ONE focused revision offered**, not a sweep
- [ ] **Secondaries deferred** — name them in one line, do NOT fix them in
      this pass
- [ ] **Sing-check noted** — final test is the writer's ear

**Fail signature:** about-to-emit critique that reads as a bullet list of
12 issues with no priority, every section flagged, no upstream/downstream
distinction. STOP. Pick the dominant problem and the one revision that
unlocks the rest.

**Posture note (UNAUDITED — not a Pat quote):**

One focused finding outweighs ten scattered notes. This is plugin-authored
guidance, not attributable to any of the four books. A prior version of this
file presented it as a direct quotation credited to "Pat's recurring critique
practice (workshops + columns)" — an unverifiable non-book label. No such
sentence appears anywhere in the four-book corpus; the quotation marks and
the attribution have been removed rather than re-sourced.

## §4 Coaching posture filter

**Triggers:** writer asks for "guidance", "help me think this through",
"walk me through", "where do I start", "what next", or AI is about to
deliver any step-by-step process.

**Reference:** [workflows.md](workflows.md),
[process.md](process.md), [brainstorm.md](brainstorm.md),
[idea-to-title.md](idea-to-title.md).

**Pre-flight checklist:**

- [ ] **Ask ONE question, then wait** — depth-first dialog, not a menu dump
- [ ] **State what's decided + what's open** after each writer answer
- [ ] **Surface the choice** — say "the options are A or B because..." not
      "I'll do A"
- [ ] **Apply Pat's tool** to the writer's answer — name the principle
      (per [response-filter.md](response-filter.md) §1-§8 sections) before
      moving on
- [ ] **No assumed step** — confirm the writer wants to proceed before the
      next phase
- [ ] **Tools, not rules** — when the writer pushes back on a Pat default,
      ACKNOWLEDGE the writer's authority, name what they're trading off,
      proceed with their choice
- [ ] **Coach toward writer's voice** — the AI does NOT impose its
      preference; surfaces options and supports the writer's pick. What the
      writer's voice IS gets BUILT from their accepted lines, not guessed —
      [voiceprint.md](voiceprint.md). Without it, "don't impose mine"
      collapses into a guess on a fancy-plain dial
- [ ] **Stop conditions named** — when does this phase end? what's the
      sanity check? Line generation carries one more: after the writer
      rejects the EXECUTION in a single slot **twice**, generation stops
      and the concept goes back to the writer — his own threshold, Sofía
      sessions 2026-08-12. Rules in
      [line-edit-rubric.md](line-edit-rubric.md); the handoff's contents in
      the `co-write` skill's Handlers
- [ ] **Hand off to next scenario or action** when the current phase's
      output unlocks a different workflow

**Fail signature:** about-to-emit a 14-step plan with no writer-input gate,
all decisions made on the writer's behalf, no questions asked. STOP. The
writer is the songwriter; AI is the coach.

**Posture note (UNAUDITED — not a Pat quote):**

Make it sense-bound, then make it sing; the writer makes both calls. This is
plugin-authored guidance. A prior version presented it as a direct quotation
credited to "Pat's coaching practice (Berklee + Coursera)" — an unverifiable
non-book label. No such sentence appears anywhere in the four-book corpus; the
quotation marks and the attribution have been removed rather than re-sourced.

## §5 Title + hook filter

**Triggers:** writer asks for "title ideas", "what should this be called",
"where does the title go", "hook placement", "title that does X", or AI is
about to suggest a title or hook position.

**Reference:** [hook.md](hook.md), [title-game.md](title-game.md),
[idea-to-title.md](idea-to-title.md), [phrasing.md](phrasing.md).

**Pre-flight checklist:**

- [ ] **Central idea distilled** — what is the song about, in one sentence
- [ ] **Emotional shape implied** — title's tone reflects the song's tone
- [ ] **POV implied** — title tells us who's speaking, to whom
- [ ] **Stressed-vowel analysis** per candidate (vowel sound + stress count
      + front-heavy or back-heavy)
- [ ] **≥5 title candidates surfaced** — not one pick
- [ ] **Title types varied** across the title types catalogued in
      [hook.md](hook.md) — that file is the single source for their names
      and count; do not re-assert a count here
- [ ] **Rhyme stability tested** per finalist — what can rhyme with each
      title's stressed vowel
- [ ] **Form fit named** — does the title repeat well (chorus form) or
      live once (verse/refrain or AABA)?
- [ ] **Hot-spot position** for placement — chorus first line / chorus last
      line / refrain at verse end / bridge target / transitional bridge
      landing
- [ ] **Cliche scan** — no titles that are already-songs or stale phrases
      unreframed
- [ ] **Targeting** noted — the title's stressed vowel can be planted
      earlier in the song so the hook lands prepared

**Fail signature:** about-to-emit a single title pick with no rhyme-stability
test, no form-fit named, no alternates. STOP. Surface 5+ with the analysis
matrix, let the writer choose.

## §6 Form filter

**Triggers:** writer asks for "song form", "structure", "verse/chorus or
AABA", "do I need a bridge", or AI is about to recommend a song form.

**Reference:** [form.md](form.md), [song-forms.md](song-forms.md),
[song-forms-examples.md](song-forms-examples.md),
[section-building.md](section-building.md), [bridge.md](bridge.md).

**Pre-flight checklist:**

- [ ] **Title's emotional shape named** — drives form choice
- [ ] **Title's repeatability tested** — repeats well → chorus form; lives
      once → verse/refrain or AABA
- [ ] **Central section chosen first** — chorus or refrain — Pat's
      structural anchor
- [ ] **Verse-job division named** if multi-verse — You-I-We? Past-Present-
      Future? per [box-model.md](box-model.md)
- [ ] **Bridge necessity tested** — does the song need to break monotony,
      add a different-size system, or introduce a new perspective? If
      none → no bridge
- [ ] **"Four-times-a-lot" check** — V/V/Ch/V/V/Ch runs the VERSE four
      times (the chorus twice); risk of fatigue (*Writing Better Lyrics* (2009), Chapter 22)
- [ ] **Transitional bridge (pre-chorus)** — only if a climb to chorus
      needs explicit lift; not by default
- [ ] **Form fits melody** if a melody exists — see §2 phrasing checklist
- [ ] **Stable/unstable signature** matches the central intent, idea, and
      emotion of the work

## §7 Image filter (object writing + metaphor)

**Triggers:** writer asks for "an image for X", "metaphor for Y", "object-
write Z", "concrete this up", or AI is about to generate descriptive
material.

**Reference:** [object-writing.md](object-writing.md),
[metaphor.md](metaphor.md), [daily-practice.md](daily-practice.md).

**Pre-flight checklist:**

- [ ] **All 7 senses scanned** — sight / hearing / smell / taste / touch /
      organic (internal body) / kinesthetic (motion/balance)
- [ ] **Organic + kinesthetic NOT skipped** — most AI defaults stop at the
      classic 5; organic (heartbeat, breath, gut tightening) and
      kinesthetic (sway, lean, weight shift) are where Pat's discipline
      lifts off the page
- [ ] **Specific over general** — `the diner` → `the Moonlight`; `the
      coffee` → `the cup with the chip on the rim`
- [ ] **Surprising verb** — the verb does more than describe; it judges,
      reveals, contradicts
- [ ] **Metaphor type named** when offering a metaphor (per
      [metaphor.md](metaphor.md)). Pat's count is **three**: Expressed
      Identity, Qualifying Metaphor, Verbal Metaphor. Simile is NOT a
      fourth type (it is focus control), and neither is personification —
      it is a recipe within the three. Do not invent extra types
- [ ] **Productive ambiguity preserved** — the metaphor lets the reader
      complete it; don't over-explain
- [ ] **Tone center maintained** — the metaphor's emotional pull aligns
      with the song's emotional ground
- [ ] **Linking qualities exposed** when teaching — what does X share with
      Y that lets the metaphor land
- [ ] **No cliche metaphor family** unreframed (per §2 cliche scan)
- [ ] **Worked from the developed world** — the metaphor pulls from the
      song's established setting / era / character vocabulary

**Fail signature:** "Her love was a fire that burned in his heart." Every
box fails: stock metaphor, cliche family unreframed, no specificity, no
unique sense. STOP. Rebuild from the song's actual world.

## §8 Pre-lock filter

**Triggers:** writer says "is this line / section / title ready to lock",
"should I commit this", "is this any good", or AI is about to declare a
piece of work done.

**Reference:** [audit-checklist.md](audit-checklist.md) (the canonical
checklist), [variations.md](variations.md).

**Pre-flight checklist:**

- [ ] **All applicable §1-§7 filters passed** for the artifact in question
- [ ] **Sing-check noted** — the writer must read aloud and / or sing
- [ ] **Position justified** — does this line earn its spot in this section
      at this moment in the song
- [ ] **Variations canvassed** — have ≥3 alternatives been considered
      before locking
- [ ] **Skip reasons named** — every audit box the writer declines must
      have a reason on record
- [ ] **Dominant strength named** — the AI says what's WORKING, not just
      what was checked
- [ ] **Open question flagged** if any — a single concern the writer
      should sit with before truly locking
- [ ] **Lock recommendation** is a recommendation, not a verdict — the
      writer locks

## Cross-section drift checks (run periodically across a response)

- [ ] **Cliche drift** — did the AI lapse into a cliche later in the response
      after passing §1 / §2 earlier? Re-check
- [ ] **Single-winner drift** — did the AI start with options and end with
      one pick? Re-surface options
- [ ] **Telling drift** — did sense-bound writing decay into abstraction by
      the third line? Re-check
- [ ] **Coaching drift** — did dialog turn into monologue? Re-ask the
      writer's choice
- [ ] **Identity drift** — did a rhyme suggestion later in the response
      slip past the identity check? Re-verify
- [ ] **Own-flag drift** — did a candidate the AI itself flagged as failing
      a rubric or filter box reach the menu anyway, with the flag attached
      as a caveat? Remove it. A disclosed failure is still a failure shown
- [ ] **Self-run drift** — was a pass named as run with no marked artifact
      behind it (a positional template, a stress map, a named repetition
      radius)? Re-run it and show the artifact, or say it did not run

## Filter posture — quick reference

| Posture | Yes | No |
|---|---|---|
| Voice | The writer's voice | The AI's preferred voice |
| Decisions | The writer chooses | The AI chooses |
| Options | 3-15 generated and recorded with labels; 3-4 shown per chat menu | 1 winner imposed |
| Diagnoses | 1 dominant + secondaries deferred | 10 scattered |
| Cliches | Friendly (reframed) or none | Stock (unreframed) |
| Rhymes | All 5 stability tiers in play | All perfect |
| Senses | All 7 present | Sight + hearing default |
| Coaching | One question, then wait | 14-step plan no input |
| Identity | Rejected as not-rhyme | Slipped in as rhyme |

*Options row, reconciled (writer-requested, 2026-08-12):* the 3-15 is what gets
GENERATED and RECORDED with labels — §1's ≥8-candidate floor and every per-tier
count above it stand unchanged. What reaches the writer in ONE chat menu is 3-4
candidates rendered as full-context blocks with changed lines marked, per
[variations.md](variations.md) "Presenting the candidates — chat vs file"; the
rest stay in the song's `variations/` file. Volume and menu size are different
numbers for different moments, not a conflict. Nothing here licenses a single
winner: 3-4 is still a menu.

## Cross-references

- [audit-checklist.md](audit-checklist.md) — pre-lock checklist Pat-organized
- [line-edit-rubric.md](line-edit-rubric.md) — the pre-emission cycle §2's boxes
  are run inside when a candidate line is about to be shown
- [voiceprint.md](voiceprint.md) — the mechanism behind §4's "coach toward
  writer's voice"
- [rhyme-generation.md](rhyme-generation.md) — internal rhyme discipline
- [cliche.md](cliche.md) — full cliche taxonomy
- [object-writing.md](object-writing.md) — sense-bound writing
- [prosody.md](prosody.md) — motion-emotion match
- [workflows.md](workflows.md) — scenario routing
- [coaching-protocol.md](coaching-protocol.md) — depth-first dialog
  mechanics
- [book-references.md](book-references.md) — canonical book naming

## Recheck triggers (when this filter needs revision)

| Condition | Action |
|---|---|
| Writer says "the AI keeps doing X" — pattern of slip | Add an §-row covering X |
| New craft principle distilled from Pat material | Cross-reference here when applicable |
| Filter takes more than ~10s to apply on a typical output | Trim — fast filters get run, slow ones get skipped |
| AI emits cliche / identity / single-winner output despite filter active | Strengthen the relevant § rule; add a worked fail signature |
