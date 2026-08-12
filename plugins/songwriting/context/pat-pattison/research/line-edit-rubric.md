# Line-Edit Rubric — Pre-Emission Cycle for Every Candidate Line

**This file is mandatory for line emission.** Before any candidate lyric line is
shown to the writer, cycle every pass below and NAME each one pass / fail /
skip-with-reason. Order matters — cheap kills first.

**What this file is.** The rubric form is this repo's, not Pat's — he never
publishes a per-candidate emission cycle. What is his is the material most boxes
invoke, and this file quotes that material from the plugin's own context files
rather than paraphrasing it. Boxes with no book source are still here, labelled
writer-derived or plugin-authored so you can tell the tooling from the books.
Every pass opens with a **Provenance:** line: Pat-anchored with a citation, or
writer-derived / plugin-authored.

**Where the form came from.** The passes and their order are the Sofía sessions
(2026-08-12), where each box exists because the writer caught a miss the
assistant should have. Two of those misses put this file here: `fountain` /
`fountain` and `filled` / `fill` same-section word collisions reached the writer
uncaught, and sonically inert candidates were presented with no sound-thread
check run at all.

**Pre-emission, not pre-lock.** This rubric runs when NOTHING has been shown to
the writer yet — the AI is gating its own about-to-emit candidate.
[audit-checklist.md](audit-checklist.md) `## Per-line checklist` runs the other
side of the same line: the writer is considering committing an existing line.
Same craft, two different moments. Neither file substitutes for the other, and
neither owns per-line checking on its own.

**Why this is a separate file and not more of §2.**
[response-filter.md](response-filter.md) is the fast gate, and its own
`## Recheck triggers` table sets the budget: "Filter takes more than ~10s to
apply on a typical output | Trim — fast filters get run, slow ones get skipped".
A full pre-emission cycle cannot live inline in a gate held to that budget
without turning the gate into the thing that gets skipped. So §2's line-writing
boxes are cycled HERE, at pass 6, when the output is a candidate line about to be
shown — one way, not two. §2 stays the owner of those boxes; if §2 changes, §2
wins.

**Tools, not rules — applied to the AI itself.** "There are no rules, only
tools." (*Writing Better Lyrics* (2009), Chapter 18). Per
[response-filter.md](response-filter.md)'s stance section, the same stance
governs the AI's self-check — with the one narrowing in the standing rules below:
a craft box the WRITER may decline is skippable when the skip is NAMED, and a
silent skip is the failure. Naming a pass as run with nothing to show for it is
also a failure.

## Standing operating rules

**Provenance:** writer-derived (Sofía sessions, 2026-08-12) — no book source. These
are the writer's own standing process rules, imposed after the session where the
assistant violated its own rubric. Do not attribute them to Pat.

1. **Nothing is shown until pass 1 is CLEAN.** On fixed-melody work a candidate
   that fails positional fit is not a candidate. It is not shown with a caveat,
   not shown as "off-template but interesting" — it is not shown.
2. **The full rubric is self-run before presentation, every time. No fatigue
   exceptions.** The failures this rule exists for: a word repeated across
   adjacent lines (`wishes` / `wish`) in violation of the rubric's own pass 2,
   and lines presented after the assistant had itself flagged them off-template.
   Under load, emit FEWER candidates — never unchecked ones. "Full" means full:
   no per-pass named skip inside the cycle. A pass whose input is missing is the
   pass that sends you to go get the input.
3. **A FAILED pass kills the candidate.** It does not reach the menu with the
   flag attached. A disclosed failure is still a failure shown, and the writer's
   attention is what the disclosure spends.
4. **Two rejections in a slot ends generation.** When the writer rejects
   execution twice for the same slot, STOP generating and hand the CONCEPT to the
   writer instead of producing a third batch. **Two** is the writer's own
   threshold; the AI does not raise it. *Slot* = the lyric position under
   revision — one line, or one section when the section is being rewritten whole;
   not the metrical or rhyme slot the craft files mean. *Rejection* = the writer
   declines the batch's EXECUTION ("none of these", "the idea's right, the lines
   aren't", no candidate picked). Picking one and asking for a tweak is not a
   rejection, and rejecting the CONCEPT resets the count, because the next batch
   answers a different brief. The writer's recurring note is "I get the idea —
   your execution is bad"; a third batch at the same execution quality spends his
   attention for nothing. What the handoff contains is specified in
   `/songwriting:co-write` Handlers.
5. **No object-write prose pasted into a lyric slot.** Object-writing output is
   ore, not lines. Pull ONE image forward, adapt it to plain sung English, and
   say it aloud before it enters a slot — the three-step rule
   `/songwriting:co-write` states as "Mine → adapt → say it aloud".
6. **The writer's sing-check is the final gate.** No pass count and no clean
   cycle makes a line good.

**Why these six are not skippable.** They are not craft boxes offered to the
writer; they are the AI checking its own output before spending his attention,
and he cannot overrule a check he never saw run. The craft-artifact gates in
`/songwriting:co-write` stay skippable-with-reason, and so do
[response-filter.md](response-filter.md)'s own §1-§8 boxes.

Menu size when candidates reach chat: 3-4 — the writer's own workspace
convention (2026-08-12), not a book number. Full pass-by-pass detail goes to the
song's `variations/` file, not inline; the presentation shape is
[variations.md](variations.md) "Presenting the candidates — chat vs file".

## 1. Positional fit (fixed-melody work only)

**Provenance:** Pat-anchored. The greedy / too-hot-too-cold test is *Essential
Guide to Lyric Form and Structure* (1991), Chapter 3, quoted below from
[audit-checklist.md](audit-checklist.md)'s per-line block; the stress material is
*Songwriting Without Boundaries* (2011), Challenge 4, from the same block; the
melody-setting scope and the template-building METHOD are
[meter.md](meter.md) "fitting a replacement line to an already-sung melody". The
empirical slot numbers are writer-derived (Sofía sessions, 2026-08-12).

This pass is the CHECK. The method that builds the template — transcribe from the
recording, scan by importance, number and bracket, compose into it — belongs to
[meter.md](meter.md); run it there and check the result here.

Pat frames this as Goldilocks — too hot, too cold, just right:

> "It is important not to be greedy: do not put stressed syllables in the
> unstressed positions. This one is too hot. […] The 'greedy' spots would
> surely get buried or at the very least sound hurried (and lose their
> emotion) when you set them to the music of the original verse. It is equally
> important to match the original's important words with equally important
> words. This one is too cold […] You must resist greed. But you must put your
> important words in the important positions. This one is just right."
> — *Essential Guide to Lyric Form and Structure* (1991), Chapter 3

That passage scopes greed one-directionally because it is matching a lyric to a
model LYRIC. This pass is the other case, and [meter.md](meter.md) states the
difference: when the lyric is being matched to a *melody* rather than to another
lyric, a mismatch in either direction is a greedy spot — a stressed syllable on a
weak beat, or an unstressed syllable riding a strong one — because either one
fights the bar. Too cold is a third failure again, and only asking what each
strong position is *carrying* catches it.

Mark the map before judging the candidate. The Sofía V1 template, measured off
the demo, in meter.md's notation:

```text
line: While  I   wan-  dered  she  watched  me   move  from  the  win-  dow  sill
scan: u      u   /     u      u    /        u    /     u     u    /     u    /
syl:  1      2   [3]   4      5    [6]      7    [8]   9     10   [11]  12   [13]
```

- [ ] **Syllable count** matched to the SUNG line, not to an inferred grid. ±1 is
      one merged or split note — allowed, but FLAGGED and priced as such
      (observed tolerance from the Sofía demo work, 2026-08-12; not a book
      number)
- [ ] **Stress POSITIONS** matched, not just the stress count. A candidate with
      the right number of stresses in the wrong slots is dead. Observed
      2026-08-12: a five-stress replacement stressing 2/4/6/11/13 was written
      against a sung line stressing 3/6/8/11/13 and died on the first
      sing-through
- [ ] **Empirically discovered hot slots honored**, not only the inferred grid.
      The writer's sung melody pushes Sofía V1's syllable 9 — the demo parks
      `from` there and it gets promoted and sticks out — so that verse's real
      template is 13 syllables with carriers at 3 · 6 · 8 · 9 · 11 · 13. Where
      the writer has stated a slot, the writer's statement is the measurement
      (writer-derived, 2026-08-12)
- [ ] **Meaning-carriers on the strong slots.** Not filler that merely avoids
      greed — this is the too-cold half, and it is a separate check
- [ ] **No road-sign word on a strong slot** — preposition, article, auxiliary,
      conjunction. Pat gives the melody-setting instruction directly: "when you
      set lyric to melody, you will remember to relegate prepositions to secondary
      rhythmic positions in the bar." (*Songwriting Without Boundaries* (2011),
      Challenge 4)
- [ ] **Compound-word stress** on the first syllable — "In English, the primary
      stress in compound words is almost always on the first syllable." (same
      challenge)
- [ ] **`ínto`, not `intó`**:
      > "Take a second to notice into, another two-syllable preposition. It is
      > stressed ínto, not intó. It is probably the most badly handled word in
      > songwriting—perhaps since it usually follows a stressed syllable […]
      > The proper handling is / She walked (pause) ínto the room."
      > — *Songwriting Without Boundaries* (2011), Challenge 4
- [ ] **Rhythm shape** (duple / triple, rising / falling) matches the sung phrase,
      and the final syllable's stress matches the melody's landing note
      *(this file's own box, not a book claim)*
- [ ] **Flagged, not absorbed** — a candidate the AI has itself judged off-template
      does not reach the menu with the flag attached. See standing rule 3

**Gate.** Pass 1 clean, or nothing is shown — see `## Standing operating rules`.

## 2. Word-repetition scan (three radii)

**Provenance:** writer-derived (Sofía sessions, 2026-08-12) — no book source.
This is the pass the file exists for. [repetition.md](repetition.md) is related
reading on what repetition DOES; it does not source these radii, and it does not
draw the named / unnamed distinction below.

- [ ] **Same section** — no repeated content word, INCLUDING inflections
      (`fill` / `filled` counts, `wish` / `wishes` counts). Kill it or justify it
      out loud
- [ ] **Adjacent-section boundary** — the last line of this section against the
      first two of the next, and the reverse. These are the junctures the ear
      holds together, so a repeat across them reads as a repeat
- [ ] **Whole song** — a repeated content word must be NAMED as deliberate: a
      through-object (the coin), or a refrain scaffold ("of Spain came coursing").
      Unnamed repetition is a defect; named repetition is a motif. The rubric does
      not forbid the repeat — it forbids the repeat nobody chose

Word repetition and sound repetition are graded oppositely: a repeated WORD is a
collision, a repeated SOUND is glue. Pass 3 is where the glue gets credit. *(This
grading pair is the writer's formulation, 2026-08-12.)*

## 3. Sonic-bonding pass (word repetition ≠ sound repetition)

**Provenance:** Pat-anchored — *Essential Guide to Rhyming* (2014), Chapter 8,
via [rhyme-sonic-bonding.md](rhyme-sonic-bonding.md), this plugin's file for
internal rhyme, assonance, alliteration, and voice leading. The boundary-stitch
and section-key boxes are writer tools (2026-08-12), marked below.

This pass sits third — ahead of the rhyme audit and the five-element delta — on
purpose. A candidate can pass every content box and still be sonically inert, and
in the Sofía sessions that is exactly what shipped. Sonic bonding is a first-class
pass here, not a cross-reference.

Pat's own name for the texture being checked:

> "Call it sonic fabric, created by placing rhymes internally. Great stuff."
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 8

And the mechanism, in his musical analogy — voice leading:

> "…where each note moves smoothly to the next, keeping common notes and moving
> the noncommon tones as few steps as possible."
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 8

- [ ] **Inside the line** — internal rhyme, assonance, or alliteration doing real
      work, or the line is sonically inert. Name the glue, or name its absence
- [ ] **Across lines in the section** — does the candidate join a sound thread the
      section already runs? (Sofía V1: the `-ill` family, the long-A chain, the
      wa/wa lead from `water` into `watched`)
- [ ] **Cross-section junctures and song-wide** — does it extend an established
      thread or break one? Voice leading works inside phrases, so it bonds lines
      without touching the rhyme scheme
- [ ] **Boundary stitch** *(writer tool, 2026-08-12 — not a book claim)*: the last
      line of a section can plant a sound that recurs EARLY in the next section's
      first line — vowel, consonant frame, or alliteration stretched across words
      — so the junction punches instead of resetting. Check both sides of any
      boundary line you touch
- [ ] **Section sonic key** *(writer tool, 2026-08-12 — not a book claim)*: name
      the section's dominant vowel or consonant thread (Sofía V1 runs short-i:
      Seville / wish / kiss, plus the `-ill` rhyme column). State whether the
      candidate JOINS the key, or breaks it and what the break buys

## 4. Rhyme audit (when the line sits in a rhyme position)

**Provenance:** Pat-anchored — identity is *Essential Guide to Lyric Form and
Structure* (1991), Chapter 4, quoted below from
[audit-checklist.md](audit-checklist.md); the stability scale is *Essential Guide
to Rhyming* (2014), Chapter 5, as printed in
[response-filter.md](response-filter.md) §1.

- [ ] **Type NAMED per pair** — no unlabeled "rhymes". Pat's printed "Scale of
      Rhyme Types: Most Stable to Least Stable" runs, in order: Perfect Rhyme →
      Family Rhyme → Additive/Subtractive Rhyme → Assonance Rhyme → Consonance
      Rhyme (*Essential Guide to Rhyming* (2014), Chapter 5, chapter-opening
      scale). Mosaic is a construction rather than a tier — name it alongside the
      tier, per [mosaic-rhyme.md](mosaic-rhyme.md)
- [ ] **Identity check** — pre-vowel consonants DIFFER, including across mosaic
      word boundaries, and no suffix-driven identity:
      > "'IDENTITY' means that syllables start the same way. 'Fuse/confuse' is
      > not a rhyme, it is an IDENTITY. Your ear does not pay attention to the
      > sounds of the syllables. There is no tension, no 'difference' to be
      > resolved by sameness. 'Peace/piece' and 'lease/police' are also
      > Identities. The same sounds are repeated, just like a cheerleader's
      > yell."
      > — *Essential Guide to Lyric Form and Structure* (1991), Chapter 4
- [ ] **Field, not column** — if this pass is choosing between rhyme partners,
      the search that produced them walked the stressed vowel's other codas, not
      only the source word's own. See [rhyme-generation.md](rhyme-generation.md)
      Step 1b; §1's third fail signature is the shape to check for
- [ ] **Scheme effect** — does this pair's stability match the section's job?
      Stability is chosen, not inherited: the Sofía V1 rebuild moved
      `filled` / `Seville` (additive) to `spill` / `Seville` (perfect) as a
      deliberate one-tier tightening, and the writer picked the tier
- [ ] **Cliche-pair scan** against Pat's own printed CLICHÉ RHYMES list, not a
      remembered one — see [cliche.md](cliche.md) and the list as quoted in
      [audit-checklist.md](audit-checklist.md)

## 5. Five-element delta

**Provenance:** Pat-anchored — Pat's own phrase is "the five basic structural
elements" (*Writing Better Lyrics* (2009), Chapter 19). He names the fifth while
setting it aside: "four of the five basic structural elements (we'll leave out
rhyme types) — an even number of lines, matched line length, stable rhythm, and
stable rhyme scheme." (Chapter 19). "Five compositional elements" is this repo's
coinage with no corpus hits; the worksheet lives at
[five-compositional-elements.md](five-compositional-elements.md) under that
filename, but do not print the coinage as Pat's.

If the edit changes any row — number of lines, line lengths, rhythm, rhyme
scheme, rhyme types — name the delta and its stable ↔ unstable consequence.

- [ ] **Row named** — which of the five moved
- [ ] **One row at a time**, the other four held fixed. This is the reading
      discipline [five-compositional-elements.md](five-compositional-elements.md)
      draws from Pat's own single-row counterfactuals: diagnose all five rows,
      change one, keep the other four fixed so you can hear what the change did
- [ ] **Line length counted in STRESSES**, not raw syllables — "line length is
      determined by the number of stresses in a line" (*Writing Better Lyrics*
      (2009), Chapter 19). A raw-syllable count answers a different question and
      invents symmetry that is not there. Pass 1's syllable numbers are an
      inventory of notes already sung, never a length claim
- [ ] **Length envelope respected** when the section was written with no fixed
      paradigm — the measured stress-length range of the song's other sections,
      per [prosody.md](prosody.md) "length envelope for a section written without
      a fixed paradigm". A line outside the envelope is a deliberate spotlight
      and gets named as one
- [ ] **Consequence stated** — stable (motion stops, closure) or unstable
      (forward motion) — and whether that is what this section's job wants. See
      [stable-unstable-meta.md](stable-unstable-meta.md) and
      [prosody.md](prosody.md)

## 6. Content boxes (response filter §2 core)

**Provenance:** Pat-anchored, and NOT a second copy.
[response-filter.md](response-filter.md) §2 owns these boxes; this pass cycles
them. Run §2 as printed there. The boxes below are the ones the Sofía sessions
found get skipped under load, listed so they are named rather than assumed — if
§2 changes, §2 wins.

- [ ] **Sense-bound** — which of the seven, said out loud. "Anything goes, as
      long as it is sense-bound. […] Use all seven senses: sight, hearing, smell,
      taste, touch, organic, and kinesthetic." (*Writing Better Lyrics* (2009),
      Chapter 1)
- [ ] **Show before tell** — "The Sister Mary Elizabeth Rule of Songwriting says:
      First, hold up Rusty's collar, and then say what you will." (*Writing Better
      Lyrics* (2009), Chapter 2)
- [ ] **Specific noun over generic label; strong verb doing real work** —
      "Verbs based in metaphor or steeped in the senses usually get the gig."
      (*Songwriting Without Boundaries* (2011), Challenge 1)
- [ ] **No abstraction in a hot spot**, and no generic universality either:
      "Songs should be universal, but don't mistake universal for generic.
      Sense-bound is universal." (*Writing Better Lyrics* (2009), Chapter 5)
- [ ] **Cliche scan + friendly-cliche test** — a cliche that stays is reframed by
      context so it earns its place, per [cliche.md](cliche.md). A flagged cliche
      is answered by reframing, never by reaching for a rarer word — see pass 8
- [ ] **Unintended implication** — read the line as a stranger with no access to
      the writer's intent, and NAME what it implies about each character. This is
      §2's window-sill lesson, and it is the box skipped precisely because the
      others passed: `she watched me from the window sill` clears sense-bound,
      specific noun, strong verb, no cliche, and consistent POV — and reads as
      surveillance
- [ ] **Nothing without its purpose** — every element the line introduces (an
      object, a second character, a place, a time marker) does a job the song
      needs. §2 grounds this in Ibsen's rule about the gun in Act I: have a reason
      for each element, and no duplication of function (*Writing Better Lyrics*
      (2009), Chapter 10)

## 7. Dependency re-verification

**Provenance:** plugin-authored — no book source. The incident: the coin-toss lost
its target when the window sill left the line, and nobody re-read line 3 (Sofía
sessions, 2026-08-12).

Every line that referenced the OLD line gets re-read against the NEW one.

- [ ] **Dependents listed explicitly** — which later or earlier lines point at an
      object, a person, an action, or a place this line used to supply
- [ ] **Each dependent verified** one at a time against the candidate AS WRITTEN,
      not against the intent behind it
- [ ] **Orphans named** — if the candidate strands a reference, either the
      candidate restores the antecedent, or the stranded lines are named in this
      response as lines that now need rewriting

## 8. Register and tone

**Provenance:** writer-derived (Sofía sessions, 2026-08-12) — no book source,
except Pat's friendly-cliche exit, quoted below. The say-it-aloud step is reuse,
not invention: [cliche.md](cliche.md)'s rewrite pattern already says "Read the
old and new lines aloud", under that file's own plugin-authored flag. This pass
promotes it from a rewrite nicety into a kill rule.

<!-- SYNTHESIS, and a naming correction carried forward from the prototype: this
     pass was titled "Register and tone" and its body used "tone" loosely. "Tone
     of voice" returns ZERO hits across all four books; audit-checklist.md and
     stable-unstable-meta.md both removed the phrase for that reason. The heading
     is kept for continuity, but the boxes below are stated as register and
     vernacular — which is what the Sofía failure actually was — and none of them
     is attributed to Pat. -->

The failure this pass exists for is not a wrong emotional colour; it is
out-of-vernacular drift. The writer caught it on `silt`: the anti-cliche
discipline overcorrects into literary or rare words nobody sings.

- [ ] **Say it out loud, talk-sung** — kill rule. Would a person SAY this? A
      precious or literary conceit can pass mechanics and fail speech
      (`bracelet's trill` did). Unsayable = rewrite, not polish
- [ ] **Bar-story test** — is this word in a bar-story telling of THIS scene, the
      words someone reaches for recounting it out loud? The writer's own
      formulation and his recorded judgements, 2026-08-12: `silt` rejected as too
      literary, `picturesque` accepted, `so` never
- [ ] **Common-word stock searched FIRST** — brainstorm from common idiom (`time
      to kill`, `sit still`, `the bill`), then reframe against cliche, per
      [line-brainstorm.md](line-brainstorm.md) "Discipline". Reaching past the
      common words entirely is the drift, not the cure. The writer's working
      premise (2026-08-12) is that modern pop sings out of the common words and
      freshness comes from STORY PLACEMENT — stated here as his premise, with no
      figure attached to it, because none is sourced
- [ ] **Not a prefer-plain-words dial** — this pass fails a word for being
      unsayable, never for being long or Latinate. `picturesque` passes, and
      `cruel` / `too` are as common as words get and were rejected as too basic
      (writer, same session). Common-but-flat content is pass 10's finding, not
      this one's; whose voice the line sounds like is not this pass's question
- [ ] **Replacing a failure stays inside the common stock and reframes**, which
      is Pat's own exit for a stale phrase: put it "in a context that brings out
      its original meaning or makes us see it in a new way" (*Writing Better
      Lyrics* (2009), Chapter 5). Escaping a cliche by escalating vocabulary is
      the overcorrection this pass exists to catch
- [ ] **Section voice matched** — talk-sung intimate verse, lifted chorus,
      interior bridge. No slang deflation of an ache (`see ya`), no formality
      spike
- [ ] **Same speaker as the section's other lines** — diction, contractions, and
      syntax consistent with what the writer has already sung

## 9. Metaphor validity (figurative lines only)

**Provenance:** Pat-anchored — [metaphor.md](metaphor.md), *Songwriting Without
Boundaries* (2011), Challenge 2 and *Writing Better Lyrics* (2009), Chapter 3.

- [ ] **Literally false?** — "Metaphors are always literally false. That's what
      makes them interesting." (*Songwriting Without Boundaries* (2011), Challenge
      2 Day 1). If it could be literally true it is description, not metaphor:
      `dark thoughts` is a metaphor, `dark eyes` is not
- [ ] **Type named — Pat's count is THREE**: Expressed Identity, Qualifying
      Metaphor, Verbal Metaphor. Simile is not a fourth type (it is focus
      control), and neither is personification (it is a recipe within the three).
      Do not invent extras
- [ ] **Expressed-identity form named** when that is the type. Pat numbers three
      forms the same way in both books, with his example word-pair:
      > 1. "x is y"        fear is a shadow
      > 2. "the y of x"    the shadow of fear
      > 3. "x's y"         fear's shadow
      >
      > — *Writing Better Lyrics* (2009), Chapter 3; *Songwriting Without
      > Boundaries* (2011), Challenge 2 Day 7
- [ ] **Focus checked if a simile was reached for** — metaphor transfers focus to
      the second term and commits the song to that world; simile keeps focus on
      the first term. A simile-only candidate is usually a metaphor the writer
      flinched from (see [metaphor.md](metaphor.md))
- [ ] **Borrowed physics named** when the metaphor works by importing another
      thing's behaviour — Sofía's `the evening spill` is verbal metaphor because
      evenings do not spill and fountains do (writer-derived example, 2026-08-12)

## 10. Spotlight content ("does it hit")

**Provenance:** Pat-anchored on the positions, writer-derived on the verdict. The
box structure, the per-candidate procedure, and the shorthand pair bright / dim
slot are plugin-authored operational scaffolding (Sofía sessions, 2026-08-12);
Pat's own words for the same thing are hot spot, power position, spotlight, and
trigger position. Everything quoted below is his, cited, and carried from
[audit-checklist.md](audit-checklist.md) and
[verse-development.md](verse-development.md).

**Where the light already is.** The section being edited fixes this before the
candidate exists. Do not rank positions — name whether the slot is one of these:

- The section's opening line and its closing line. "Beginnings and endings. Two
  HOT SPOTS. […] Whatever ideas you put in HOT SPOTS become your most important
  ideas. You make them important by putting them there."
  (*Essential Guide to Lyric Form and Structure* (1991), Chapter 7)
- The closing line of a verse running into a chorus or refrain — Pat's **trigger
  position**: "it releases us into the chorus, carrying whatever the line says
  with us" (*Writing Better Lyrics* (2009), Chapter 7)
- A structural surprise. His Moral names exactly three families and no more:
  "opening positions, closing positions, and surprises, like shorter, longer, or
  extra lines" (*Writing Better Lyrics* (2009), Chapter 7). Do not add a fourth
  kind of surprise — [verse-development.md](verse-development.md) records the
  inflated eight-item version that was removed from this corpus.
- A rhyme position, a spotlight in its own right (*Essential Guide to Rhyming*
  (2014), Chapter 2). The empty-rhyme case belongs to
  [rhyme-spotlight-connection.md](rhyme-spotlight-connection.md) and is not
  restated here.

Every other slot is dim, and a flat line in a dim slot is not this pass's
finding. Where two of the above coincide, both apply; there is no scale and no
tier.

**The test — Pat's reduction, narrowed to one candidate.** The reduction is his;
the narrowing to a single unshown line is the plugin's. His pass/fail line:

> "If you can get a good idea of a lyric's meaning just from spotlight
> information, you are using your rhyming positions effectively."
> — *Essential Guide to Rhyming* (2014), Chapter 2

and *Writing Better Lyrics* (2009), Chapter 7 runs the same reduction on whole
sections, printing both verses of "Child Again" stripped to their four power
positions alone — "Each verse works beautifully to set up its special view of
the chorus." Run it on the candidate:

1. List the section's power positions per the block above.
2. Substitute the candidate into its slot; leave every other position as it
   stands.
3. Read only those positions, in order, and nothing else.
4. Ask whether the section's argument still arrives from that reading.

If the reduced read goes slack or silent exactly where the candidate sits, the
candidate FAILS. Print the reduced read back and name the position; a verdict
without the reduced read shown is not this pass run.

**Fail signature — competent-flat in a bright position:** a candidate that is
sense-bound, specific, strong-verbed, cliche-free, and consistent in POV, and
still says nothing the section needed. Production-observed, the writer's own
finding and not Pat's: `I still don't know her last name` (Sofía sessions,
2026-08-12) passed every other box in this rubric, and the section's closing
spotlight lit an absence. This is the discrimination against the content boxes
(pass 6): those kill abstraction and cliche in a hot spot; this one fires only
where all of them already passed.

**Remedy — rewrite or demote. There is no third option.** Demote means both
halves: move the flat content to a dim slot AND put something that earns the
light in the bright one. That placement alone is a real lever is Pat's, shown as
a failure rather than a recommendation — Chapter 7 redistributes "Child Again"
verse 1's own information into weaker slots, adding and cutting nothing, and the
untouched chorus changes meaning: "the ideas haven't really changed, only their
placement has changed" (*Writing Better Lyrics* (2009), Chapter 7). He is not
prescribing demotion; he is proving the slot decides what the section is about,
which is what makes demotion a fix here and not a dodge.

**Not the same box as [response-filter.md](response-filter.md) §3.** §3 works on
a finished draft: find the positions the structure has already marked, then name
whatever content is sitting there. This pass works on a candidate not yet shown,
in a slot whose brightness the section fixed before the rewrite began. The §3
question is *which positions are marked*; this one is *does this line earn the
light this slot is already throwing*.

## 11. Voiceprint match — "does this sound like THIS writer said it?"

**Provenance:** writer-derived (Sofía sessions, 2026-08-12) — no book source. The
build procedure and the artifact it judges against are
[voiceprint.md](voiceprint.md), which states plainly that Pat publishes no such
method.

Judged against the writer's voiceprint (`songwriting/shared/voiceprint.md`), never
against genre and never against "good line". This pass sits last because it is the
closest proxy the rubric has for the writer's own ear, so it stands next to the
sing-check that settles everything. Name the dimension the candidate is tested on
AND the accepted line that sets the standard:

- [ ] **Vocabulary band** — every multisyllable in the candidate: does it PAY, by
      the standard of the writer's accepted lines? Quote the accepted line it is
      measured against. Every plain word: does it carry weight, or is it below the
      writer's floor?
- [ ] **Syntax shape** — is this a sentence form that actually appears in the
      accepted corpus, or one the AI reached for?
- [ ] **Image density** — does the line's concrete-image count sit inside the
      writer's band, or is it thinner or more crowded than their accepted lines
      run?
- [ ] **Irony level** — same distance between what the speaker says and what the
      song means as the accepted lines hold?
- [ ] **Rejection check** — does the candidate reuse a word or a move already on
      the writer's recorded rejection list? A repeat of a named rejection is an
      automatic fail, not a judgement call

If no voiceprint exists, this pass is SKIPPED WITH THE REASON NAMED ("no
voiceprint on disk") — not silently passed. A pass claimed with no artifact to
judge against is a failed pass. This is the one pass whose skip is legitimate,
because its input lives in the consuming project and may not have been built yet.

**Distinct from pass 8.** Pass 8 asks whether the line fits the SECTION's voice —
whether it is speakable in this slot. This pass asks whether it fits the WRITER's,
across every song and every speaker they write. A line can sit perfectly in a
talk-sung verse and still be a line this writer would never say, and the reverse
is equally possible. Neither pass acquires the other's test.

## Then: sing-check

The writer sings it against the melody. **The rubric filters; the ear decides.**

The AI cannot sing, so this is not politeness — it is the one measurement the
rubric cannot take. Pat makes singing the settling test twice in *Essential Guide
to Rhyming* (2014), Chapter 5 alone:

> "Never stop listening. If your ear says a sound is wrong, find another
> rhyme. Trust your ears. (But be sure to sing your rhymes when you check.)"
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 5

> "Again, sing them. Trust your ears."
> — Pat Pattison, *Essential Guide to Rhyming* (2014), Chapter 5

## Where a rubric run goes

*This section is this file's own operational convention, not a book claim.*

Per [artifact-persistence.md](artifact-persistence.md), a run's output lands in
the song's `variations/<section>-<line>.md` as part of that file's labeled menu —
the pass results sitting next to the candidate they graded, so a later reader can
see which boxes a locked line actually cleared. Chat gets the candidates in
context; the pass-by-pass detail lives in the file.

## Cross-references

- [response-filter.md](response-filter.md) — §2 owns pass 6's content boxes; this
  file cycles them for pre-emission candidates
- [voiceprint.md](voiceprint.md) — pass 11's artifact and the procedure that
  builds it from the writer's accepted lines
- [audit-checklist.md](audit-checklist.md) — the PRE-LOCK counterpart; its
  `## Per-line checklist` runs on a line the writer is already considering
  committing
- [meter.md](meter.md) — pass 1: greedy spots in the melody-setting frame, and
  the method that builds the positional template
- [rhyme-sonic-bonding.md](rhyme-sonic-bonding.md) — pass 3: internal rhyme,
  assonance, alliteration, voice leading, sonic fabric
- [rhyme-types.md](rhyme-types.md) — pass 4: the stability tiers in full
- [rhyme-fundamentals.md](rhyme-fundamentals.md) — pass 4: identity-vs-rhyme
  origin
- [rhyme-generation.md](rhyme-generation.md) — pass 4: the vowel-field walk that
  produces the partners
- [mosaic-rhyme.md](mosaic-rhyme.md) — pass 4: mosaic construction and its risks
- [five-compositional-elements.md](five-compositional-elements.md) — pass 5's
  worksheet
- [prosody.md](prosody.md), [stable-unstable-meta.md](stable-unstable-meta.md) —
  pass 5's stable ↔ unstable consequence and its length envelope
- [cliche.md](cliche.md) — the cliche lists passes 4, 6 and 8 check against
- [line-brainstorm.md](line-brainstorm.md) — pass 8's common-stock-first
  generation order, and the high-volume dump this rubric filters
- [metaphor.md](metaphor.md) — pass 9's three types and the literally-false test
- [verse-development.md](verse-development.md),
  [rhyme-spotlight-connection.md](rhyme-spotlight-connection.md) — pass 10's
  power positions and the rhyme-position spotlight
- [repetition.md](repetition.md) — related reading for pass 2 (repainting,
  productive repetition); it does not source pass 2's radii
- [variations.md](variations.md) — the labeled-menu format and the chat-vs-file
  presentation shape surviving candidates go into
- [artifact-persistence.md](artifact-persistence.md) — where a run is written
- [book-references.md](book-references.md) — canonical book naming
