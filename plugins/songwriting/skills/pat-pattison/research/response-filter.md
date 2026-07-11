# AI Response Filter — Pre-Flight Gate for Every Output

**This file is mandatory.** When `/pat-pattison` skill is active — explicitly or
auto-routed — every AI response that suggests rhymes, writes a line, rewrites
a lyric, critiques a draft, or coaches process MUST pass through the
applicable section below before emission.

The filter exists because generic LLM defaults — perfect rhymes, predictable
end-lines, abstract telling, cliche imagery, single-winner picks — directly
violate Pat Pattison's craft. The filter activates the discipline already
captured in the other context files. It is the gate, not new craft.

## Stance: Tools, Not Rules — applied to the AI itself

> "Tools, not rules." — Pat Pattison (recurring column / seminar framing)

The filter is a tool the AI uses to check its own work. The AI may skip a box
when justified — but a skip must be NAMED. Silent skips are not OK.

When the AI applies the filter and finds nothing applicable, it says so out
loud: *"Filter scan: no rhyme position, no abstract telling, no hot-spot
exposure — clear to emit."* Naming the no-op proves the gate ran.

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
| Critique / diagnosis of an existing lyric | §3 Critique filter |
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
- [ ] **Identity check** on every candidate — pre-vowel consonants DIFFER
      from the source word (e.g., `time / sometime` = identity, REJECTED;
      `time / rhyme` = rhyme, accepted). Identity check applies ACROSS
      multi-word boundaries for mosaic candidates too (`Texas / text us`
      = identity-in-disguise, REJECTED; `Texas / wrecks us` = rhyme).
- [ ] **No suffix-driven identity** sneaking through (`-ation`, `-ing`,
      `-tion`, `-ly`, `-ness` chains routinely produce identities)
- [ ] **≥4 stability tiers surfaced** — perfect / family / additive-
      subtractive / assonance / consonance — not all perfect
- [ ] **MOSAIC tier MANDATORY** — ≥3 mosaic candidates surfaced per
      [mosaic-rhyme.md](mosaic-rhyme.md), regardless of source word.
      Cross-part-of-speech (verb+pronoun, adjective+noun, imperative phrase,
      contraction stack) included. Proper-noun mosaic considered when
      the song's world allows. The AI's default is single-word-rhyme; the
      filter forces mosaic onto the table.
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
- [ ] **Sing-check noted** — the AI cannot sing; the WRITER must sing-check

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

**Anchor quote:**

> "When you cheat the rhyme, you cheat the ear. The ear is the boss."
> — Pat Pattison (recurring teaching, *Essential Guide to Rhyming* (2014))

## §2 Line-writing filter

**Triggers:** writer asks for "a new line", "rewrite this line", "alternative
phrasing", "say this differently", "variations", or AI is about to emit
any prose lyric line.

**Reference:** [object-writing.md](object-writing.md),
[cliche.md](cliche.md), [phrasing.md](phrasing.md), [meter.md](meter.md),
[hook.md](hook.md), [variations.md](variations.md).

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
      front-heavy/back-heavy choice)
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
- [ ] **Identity ≠ rhyme** if line sits in a rhyme position — pre-vowel
      consonants on the rhyme word DIFFER from any prior rhyme partner
- [ ] **Pronoun consistent** with section's established speaker / audience
- [ ] **Camera distance** matches section role (close-up for verse intimacy,
      middle for narrative, long-shot for chorus universality — or
      deliberate hybrid)
- [ ] **Tone-of-voice** stable — same speaker, same emotional register as
      the section's other lines
- [ ] **Vowel awareness** — the line's stressed vowels chosen, not
      defaulted; bright vowels (long-ē, long-ā) feel sharp; dark vowels
      (long-ō, long-ū) feel weighted

**Fail signature:** about-to-emit line like *"My broken heart is lonely in
the dark, waiting for your love to make me whole"* — every box fails:
abstract telling, three cliches, generic nouns, no senses, weak verbs.
STOP. Rebuild from a concrete sense-bound image.

**Anchor quote:**

> "Sense-bound is universal. Generic is not."
> — Pat Pattison (recurring teaching, *Writing Better Lyrics* (2009),
> Chapter 1)

## §3 Critique filter

**Triggers:** writer asks for "review", "diagnose", "what's wrong with this",
"honest feedback", "Pat would say what", or AI is about to deliver findings
on a draft.

**Reference:** [demo-review.md](demo-review.md),
[audit-checklist.md](audit-checklist.md),
[five-compositional-elements.md](five-compositional-elements.md),
[stable-unstable-meta.md](stable-unstable-meta.md).

**Pre-flight checklist:**

- [ ] **Section types identified** — verse / chorus / bridge / refrain /
      transitional bridge — auditing a refrain like a chorus is the
      wrong test
- [ ] **Read aloud once** before analysis — first pass is sensation, not
      diagnosis (note: writer reads; AI flags this as a step)
- [ ] **Five Compositional Elements counted** per section (lines, line
      lengths, rhyme scheme, rhyme types, rhythm)
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

**Anchor quote:**

> "One focused finding outweighs ten scattered notes."
> — synthesized from Pat's recurring critique practice (workshops + columns)

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
      preference; surfaces options and supports the writer's pick
- [ ] **Stop conditions named** — when does this phase end? what's the
      sanity check?
- [ ] **Hand off to next scenario or action** when the current phase's
      output unlocks a different workflow

**Fail signature:** about-to-emit a 14-step plan with no writer-input gate,
all decisions made on the writer's behalf, no questions asked. STOP. The
writer is the songwriter; AI is the coach.

**Anchor quote:**

> "Make it sense-bound. Then make it sing. The writer makes both calls."
> — synthesized from Pat's coaching practice (Berklee + Coursera)

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
- [ ] **Title types varied** across Pat's seven (per [hook.md](hook.md)):
      central-idea / image / verb / question / command / direct-address /
      paradox-or-irony
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
- [ ] **"Four-times-a-lot" check** — V/V/Ch/V/V/Ch has the chorus four
      times; risk of fatigue (*Writing Better Lyrics* (2009), Chapter 22)
- [ ] **Transitional bridge (pre-chorus)** — only if a climb to chorus
      needs explicit lift; not by default
- [ ] **Form fits melody** if a melody exists — see §2 phrasing checklist
- [ ] **Stable/unstable signature** matches central emotion

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
      [metaphor.md](metaphor.md)): adjective-noun / noun-verb / expressed
      identity / simile / linking quality
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

## Filter posture — quick reference

| Posture | Yes | No |
|---|---|---|
| Voice | The writer's voice | The AI's preferred voice |
| Decisions | The writer chooses | The AI chooses |
| Options | 3-15 surfaced with labels | 1 winner imposed |
| Diagnoses | 1 dominant + secondaries deferred | 10 scattered |
| Cliches | Friendly (reframed) or none | Stock (unreframed) |
| Rhymes | All 5 stability tiers in play | All perfect |
| Senses | All 7 present | Sight + hearing default |
| Coaching | One question, then wait | 14-step plan no input |
| Identity | Rejected as not-rhyme | Slipped in as rhyme |

## Cross-references

- [audit-checklist.md](audit-checklist.md) — pre-lock checklist Pat-organized
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
