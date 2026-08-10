# Changelog

All notable changes to the `songwriting` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.8.4]

A source-fidelity pass over *Essential Guide to Lyric Form and Structure*
(1991) Chapter 3 (Rhythm), read in full with **all 59 of its figures**, against
`meter.md` and `prosody.md`. This chapter is the book's densest and it argues
almost entirely in page scans, so the figures are where nearly every finding
below came from. Paraphrase only; no chapter prose, example lyrics, or exercise
answers reach this public repository.

### Fixed

- **`meter.md`'s image inventory said this chapter has "no linked page-scan
  images." It has 59 references across 56 unique figures.** This is the **third**
  chapter whose inventory carried that exact falsehood, after Chapter 6 (37
  figures) and Chapter 5 (32) in 0.8.3. Every scansion, all three Paradigms, the
  4/4 bar settings, and all four filled-in Structural Pentad worksheets exist
  only as images. The two corrections immediately below were invisible to a
  text-only reader and both survived a full prior pass because of that one line.
- **The scansion worked example marked the wrong number of stresses.** "When I
  got home the house was dark" was scanned with "got" stressed, giving four
  stresses. Pat's figure marks "when," "I," and "got" all unstressed: **three
  stresses**. The code block also contradicted the file's own prose two lines
  below it, which already described "got" as a grey-area syllable. This is the
  model scansion the skill hands users, so it was teaching the error.
- **"Too cold" was defined as a stress failure. It is not a stress failure at
  all.** `meter.md` had it as "an unstressed syllable where the structure wants
  stress." Pat's too-cold example preserves the model's stress map exactly; what
  fails is that the important positions are filled with semantically empty
  words. The two Goldilocks states test **two independent things** — the stress
  map, and what stands on each strong position — and "just right" requires both.
  A rewrite can scan perfectly and still be dead, which is precisely the failure
  a stress-only audit cannot see. `meter.md` already stated this correctly in its
  pattern-matching section; the later section contradicted it. **Fifth file found
  with the correct-early / wrong-late duplication shape**, after `song-forms.md`,
  `co-writing.md`, and `phrasing.md`.
- **The emitted Pentad worksheet offered values that are not in Pat's
  worksheet.** Balance was `balanced | unbalanced` where the source's closed list
  is **symmetrical | asymmetrical**, and Closure offered a third value,
  `leans forward`, where the source is **binary: closed | open**. The file's own
  summary section had both right; the copy-paste block users actually receive had
  both wrong. Value lists are now stated as closed lists, with a filled-in table
  for all three Paradigms.
- **The Pentad's cross-domain claim generalized past its evidence — in a section
  a previous release had already corrected.** Pat names three surfaces:
  rhythmic, rhyme, and *musical*. `meter.md` split the third into "melodic
  structure" and "harmonic structure (chord pattern stability per pentad
  property)," inventing per-surface criteria that are not in the source. 0.8.2
  fixed a different defect in this same section and the overreach survived.
  Readers wanting melody- or harmony-specific stability criteria are now pointed
  at `stable-unstable-meta.md`, which genuinely carries them.
- **"Greedy spot" was defined inconsistently across five files, and its scope
  turns on a frame nothing stated.** Matching a lyric to a *model lyric*, greed
  is **one-directional** — stressed syllables in unstressed positions, the
  too-hot failure only; Pat names the opposite error separately as "too cold"
  and never calls it greed. Matching a lyric to a *melody*, **either** direction
  is a greedy spot, since a stressed syllable on a weak beat and an unstressed
  syllable riding a strong one both fight the bar. Three distinct failures,
  three distinct fixes — and too cold is caught by no stress check at all.
  `meter.md`, `prosody.md`, `audit-checklist.md`, `lyric-melodic-roadmaps.md`,
  and `skills/meter-prosody/SKILL.md` now each name their frame.
  `skills/meter-prosody/SKILL.md` had also carried a definition attributable to
  no source, "too many syllables for the melodic slot."
- **`lyric-melodic-roadmaps.md` contradicted itself on the same term.** Its
  definition covered only stressed-on-weak while its own worked example
  diagnoses an unstressed syllable riding a strong beat as a greedy spot. The
  definition now covers both directions. Pre-existing; surfaced by review.
- **Two categorical claims had been softened into hedges.** Three-syllable words
  with middle primary stress have **no** secondary stress, not "may be no"; words
  of four or more syllables **always** carry secondary stress, not "normally."
- **`demo-review.md` attributed the Pentad to `five-compositional-elements.md`.**
  That is the two-lists confusion 0.8.2 fixed in `meter.md`; it survived here.
  The Pentad (balance, pace, flow, closure, type of closure) lives in `meter.md`;
  the Elements are a different five-item list naming the levers.
- **A header note claimed Pat has no notation for unstressed syllables.**
  `meter.md` stated that "Pat's own source notation uses only `/` and `//`" and
  that the `u` marker "is not in Pat's text." Pat marks unstressed syllables with
  a breve throughout, and this chapter's exercises ask for that "slight cup" over
  the vowel by name. `u` is an ASCII stand-in for it, not an addition.

### Added

- **Phrase length measured in stressed syllables now shows the inversion.** The
  file said an extra weak syllable "may not change the structural weight," which
  understates the source: an 8-syllable / 4-stress phrase is **longer** than a
  9-syllable / 3-stress phrase. Raw syllable count can rank a pair backwards,
  which is the entire reason this method counts stresses.
- **The rule for counting secondary stress when scanning.** A secondary stress
  counts as a stress. Without it the file's own common-meter example miscounts as
  three stresses instead of four, and the paradigms break on any multi-syllable
  word.
- **The rule that unstressed pickups do not change the pattern.** Anacrusis at
  the head of a line leaves a 4/3/4/3 stanza at 4/3/4/3.
- **The third deceleration case.** The file covered only triple-to-duple. *Any*
  reduction in unstressed syllables decelerates, including dropping them entirely
  so stresses fall adjacent. The single mechanism behind both directions — strong
  stresses hold their musical positions while the space between them crowds or
  opens — is now stated once, where the effect is described.
- **Paradigm 1 stated in triples alongside duples**, which is the cleanest proof
  that the paradigms are defined by stress count rather than syllable count, and
  is what the chapter's own exercises drill.
- **The one-word demonstration inside the common-meter example.** Lengthening
  line two to four stresses makes the first two lines balanced and stoppable;
  leaving it at three is what makes the form move. This claim exists only in a
  figure — the surrounding prose is a dangling reference to it — and it is also
  the bridge to Paradigm 2.
- **A note that Paradigm 3 still closes.** Deception is a property of the type
  row, not the closure row, and it works only because the resolving phrase length
  is already present in the structure.

### Notes

- **Verified, no change needed:** the conventional-stress examples
  (`incision`, `turbulent`, `understand`, `relinquish`) all match their figures,
  and Chapter 3 does own Exercises 8-17 as `meter.md` claimed.
- **Two open probes were aimed at the wrong chapter.** "Can't Fight This
  Feeling" does not appear in Chapter 3; it appears in Chapters 1, 5, and 7, and
  Chapter 1's use is a phrase-count argument, not the stress-pattern claim
  `section-building.md` makes. "Years" appears in Chapters 2 and 5, not 3, so
  `form.md`'s composite-balance claim must be checked against Chapter 5. Both
  left unadjudicated rather than hedged.
- `meter.md` is now a **third** file carrying duplicated parallel treatments of
  the same material — two Pentad sections and two Paradigm sets. They were
  reconciled here rather than folded together, since the duplication itself is
  scoped as a separate restructuring follow-up alongside `song-forms.md` and
  `phrasing.md`. That duplication is what allowed the worksheet and the summary
  to disagree about Pentad values in the first place.

## [0.8.3]

A source-fidelity pass over *Essential Guide to Lyric Form and Structure*
(1991) Chapters 1, 2, and 6, each read in full with every figure, plus
Chapter 5's bridge and song-system material. **This opens Book 1** and settles
the two claims the 0.8.2 pass had to leave standing. Paraphrase only; no
chapter prose, example lyrics, or exercise answers reach this public
repository.

### Fixed

- **"Four times is a lot" was credited to 1991 Chapter 6 as a shared warning.
  It is 2009's alone.** Chapter 6, read in full with its 37 figures, never
  discusses V/V/Ch/V/V/Ch, never counts verses, and never names four. Its
  related claim is about pattern-size monotony, not verse-exposure count.
  `song-forms.md` now scopes the warning to *Writing Better Lyrics* (2009),
  Chapter 22, states what 1991 actually says instead, and attributes the bare
  pull-quote that had been sitting uncited near the top of the file.
- **"Southern Comfort" was read as seven phrases with the eighth withheld. The
  verse has eight, and the eighth arrives.** The rhyme-column and scansion
  figures are unambiguous: eight phrases rhyming `x a x a x a b b`. Nothing is
  withheld in phrase *count* — the eighth phrase lands and refuses the
  three-stress common-meter close and the rhyme resolution the first seven set
  up, which is what makes it a Deceptive Closure. Corrected in
  `song-forms-examples.md` and `song-forms.md`.
- **The resulting standoff in `form.md` is dissolved, not re-hedged.** 0.8.2
  recorded 2009 Chapter 20's "two common-meter systems" and the 1991 "seven
  phrases" reading as two coexisting readings not to be merged. With the 1991
  text verified, both books read **eight**; they differ only in vocabulary
  (extra stress in the final phrase vs. deceptive closure). The instruction to
  keep the counts apart is removed.
- **Two image inventories claimed their 1991 chapter has no linked images.
  Chapter 6 has 37 and Chapter 5 has 32, and in both the figures carry the
  argument.** The scansion and rhyme-column analysis lives in the figures while
  the text layer trails off at dangling colons. `song-forms.md`'s false entry is
  how the seven-phrase error survived a previous pass; `form.md` carried the
  same falsehood for Chapter 5. Both now state the real count. `form.md`'s entry
  also records that Chapter 5 has *not* been read in full, so claims sourced to
  it are not mistaken for verified.
- **The three bridge functions were cited to Chapter 5; they are Chapter 6's.**
  Book 1 carries two different bridge lists and the plugin had merged their
  labels. `bridge.md` now cites Chapter 6 for the three purposes, and records
  Chapter 5's separate five-point characterization of what a bridge *is* so the
  two stop being conflated. Same fix in `song-forms-examples.md` and
  `song-forms.md`.
- **"Different-size system" had been relocated from the song system to the
  bridge.** Chapter 6's claim is about the *song system's* size, not the
  bridge's own phrase count or line length — and Pat's word is **different**,
  not shorter. The direction depends on the form: in verse/chorus a short
  bridge makes the last system shorter so the final chorus arrives early, while
  in verse/refrain and AABA the bridge-plus-final-verse system is *longer* than
  the verse-only systems before it. Corrected in `bridge.md`, `form.md`, and
  `templates/bridge-writing-prompt.md`.
- **All four jointly loaded bridge consumers now agree.**
  `/songwriting:song-form bridge` loads `bridge.md`, `form.md`,
  `templates/bridge-writing-prompt.md`, and `song-forms.md` together; the
  Chapter 5 attribution and the phrase-count reading of function 2 survived in
  `form.md` and the template, so a single invocation would have supplied
  contradictory sourcing and diagnostics.
- **`phrasing.md` stated Chapter 1's spotlight use twice and got it wrong the
  second time.** The early section has it right — the balancing position is the
  last phrase of an *even* section, and stopping is what spotlights. The later
  appended block said the balance *shift* is the spotlight, which is Chapter
  1's third use, not its first. Fourth file found with this
  correct-early/wrong-late shape.
- **The even/odd balance rule was stated without either of Pattison's own
  overrides.** Nesting can rescue an odd count (the five-phrase "Fathers and
  Sons" verse seems balanced because two short phrases add up to one long one);
  closure behavior can unbalance an even one ("Southern Comfort" at eight).
  Applied mechanically, the bare rule misdiagnoses both of his examples.
- **Acceleration and deceleration were presented as an exclusive choice.** The
  "Slow Healing Heart" case speeds up, returns to pace, then slows; Pattison is
  explicit that more than one blank gets filled. The practice method said to
  pick one label.
- **"The spotlight effect is multiplicative, not additive" is not Pattison's
  claim.** He says the surprise phrase spotlights both lines, *especially* the
  last. The invented framing and the dropped ranking are both corrected.
- **Chapter 2's exercises were missing entirely.** `exercises.md` claims to
  preserve the numbered series for Chapters 1-7, but ran 1, 2, 3, 4 and then
  jumped to 8 — the gap is exactly Chapter 2's three. Added Ex 5 (label the
  pace effect, filling more than one blank where earned), Ex 6 (complete a
  section accelerating, then decelerating), and Ex 7 (contrast a whole section
  by phrase length), generalized in the style of Ex 1-4.
- Doubled year in two headings (`exercises.md`, `five-compositional-elements.md`)
  left by a mechanical book-title substitution.

### Added

- `phrasing.md` — two unbalanced sections can balance each other; Pattison's
  stated use for motion pairs one unbalanced section with another equally
  unbalanced one, so odd sections need not be discharged by an even one.
- `phrasing.md` — the reversal test: swap a verse pair and see whether the push
  survives. If it does not change, the imbalance is not doing the work.
- `song-forms.md` — Chapter 6 states its two form principles as a pair. AABA
  runs on the limerick's principle and verse/chorus on Common Meter's, also
  called the Ballad Stanza; only the first half was recorded.

## [0.8.2]

A source-fidelity pass over `process.md`, `co-writing.md`, and the co-write
session-opener template against *Writing Better Lyrics* (2009) Chapter 24 and
the Appendix, both read in full with Chapter 24's two figures. **This finishes
Book 2.** Paraphrase only; no chapter prose, example writes, or student work
reaches this public repository.

### Fixed

- **The No-Free-Zone method was attributed to Pat throughout; it is Stan
  Webb's.** The Appendix is emphatic — Webb taught it to Pat in his first
  professional co-write, and the Appendix thanks him by name. Pat carried it
  into Berklee and added two rules of his own (stay inside the song; no
  technical talk). `co-writing.md` and the printable opener now credit Webb,
  and the opener's title line no longer calls the method Pat's.
- **The session opener collapsed Webb's two distinct rules into one and lost a
  rule in the process.** "Say everything" and "nobody says no / silence means
  more" are separate rules doing separate jobs; merging them under a single
  `No "no."` heading left "write crap" occupying a numbered slot as if it were
  a third rule rather than the encouragement attached to the first two. The
  four numbered rules now match `co-writing.md`.
- **`co-writing.md`'s inner-critic section and its solo-applications section
  contradicted each other** on which rules apply when writing alone — two of
  four versus all four. The Appendix supports the looser reading (the
  discipline helps every time Pat writes; the inner critic is his most frequent
  co-writer), so the disagreement is now stated explicitly with the Appendix's
  own evidence rather than left for a reader to trip over.

### Added

- **`co-writing.md`: the causal claim the rule rests on.** The chain is dumb
  idea → less dumb → decent → great, and the Appendix reports its own session's
  best part came from its dumbest idea. The file had the mechanism but not the
  claim that censoring the first link forfeits the last.
- **`co-writing.md`: what the closed door actually buys** — nobody defends
  anything, so surviving ideas are the ones both writers love; no arguments and
  no compromise.
- **`co-writing.md` + opener: technical talk is fear wearing academic robes.**
  The Appendix diagnoses it as a writer dressing up a line they suspect is
  weak, which makes it a signal to read rather than a lapse to scold.
- **`process.md`: five named rejection criteria from Chapter 24's worksheet
  walk-through**, including the "seems to mean more than it conveys" clunker
  test, plus the rule that the rhyming syllable should carry primary and not
  secondary stress. None of these existed anywhere in the plugin.
- **`process.md`: pattern lock as a named failure mode.** Chapter 24's bridge
  came out in the verses' common meter on autopilot; the chapter also catches
  itself borrowing a specific Paul Simon bridge structure and notes that
  loving the source does not make the borrow work.
- **`process.md`: the form option that LOST and why.** Dumping a verse is
  tested first and rejected on cause — form repairs are subject to scene logic,
  so a leaner form that breaks cause is not an improvement.
- **`process.md`: the worksheet is a brainstorming device, not a rhyme-finding
  device** — stated outright in Chapter 24, with Sondheim cited as a working
  practitioner.
- **`process.md`: Chapter 24's worksheet figure is load-bearing.** The prose
  lists the five column headings and nothing under them; the columns exist only
  in `image_rsrcAUJ.jpg`, which independently confirms the
  one-undifferentiated-column-per-core-word layout recorded in `worksheets.md`.

## [0.8.1]

A source-fidelity pass over `song-forms.md` and `form.md` against *Writing
Better Lyrics* (2009) Chapters 20-23, all four read in full — including
Chapter 20's figure and all four of Chapter 21's split spine items. Paraphrase
only; no chapter prose, example writes, or student work reaches this public
repository.

### Fixed

- **A late-appended block in `song-forms.md` restated the Chapter 22 and 23
  repair strategies and got four of the six wrong**, each one contradicting the
  correct statement earlier in the same file. Chapter 22's third repair merges
  two verses into one larger verse that shifts internally, leaving two verses;
  the block described giving four verses four different jobs, which preserves
  the very `v/v/ch/v/v/ch` shape the chapter exists to dismantle. Its second
  repair kept "same content" when the chapter requires changing both structure
  and the kind of information, the distinction that separates a bridge from a
  renamed verse. Chapter 23's second alternative replaces the third verse; the
  block had verse three still building normally. Its third alternative converts
  to AABA precisely so all three verse ideas survive as verses; the block said
  to drop the third verse — the opposite of the condition that selects the
  form. Each repair now states its resulting form explicitly so the two
  descriptions cannot drift apart again.
- **"Four times is a lot." was attributed to the wrong book and labelled a
  paraphrase.** It is verbatim from *Writing Better Lyrics* (2009), Chapter 22.
  The claim that *Essential Guide to Lyric Form and Structure* (1991)
  Chapter 6 shares the warning is left standing but remains unverified — that
  chapter has not been read.
- **The chapter title was rendered "Im(potent) Packages"**, parenthesising the
  wrong half of Pat's pun. It is "(Im)potent Packages".

### Added

- **`form.md`: Pattison's own naming of the two form-follows-function
  readings.** Applied to one section the rule *is* prosody; applied to two
  sections compared against each other it *is* contrast. The file had the
  mechanics of both but had dropped the link to the plugin's own prosody
  vocabulary.
- **`form.md`: the musical-bar mechanism behind the "Years" chorus.** The file
  had the stress arithmetic balancing at six and six, but the prosody lives in
  the setting — both groups get four bars, so three phrases occupy the space
  two had, and the final phrase is compressed to a single bar exactly where the
  lyric says time moves fastest.
- **`form.md`: a contrast-audit caution drawn from the "Southern Comfort"
  chorus.** Three-stress phrases and a "3+" opening can look like contrast
  while still leaning toward the common meter the verse established, because
  three stresses is that meter's balancing length.
- **`song-forms.md`: an AABA song's last system is bridge/verse, not a lone
  verse** (Chapter 23) — the pairing supplies the contrast against the opening
  A sections, so an unearned-feeling return should be diagnosed across the
  whole B-to-final-A unit.
- **`song-forms.md`: the cost Chapter 23 attaches to its first alternative** —
  inserting a bridge before a third verse returns to a full verse before the
  last chorus, so the lyric can still seem long.

## [0.8.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.7.4]

A source-fidelity pass over `object-writing.md` (Chapter 2), `worksheets.md`
(Chapter 4), and `cliche.md` (Chapter 5) against *Writing Better Lyrics* (2009),
all three read in full with their figures. Paraphrase only; no chapter prose,
example writes, or student work reaches this public repository.

### Fixed

- **The worksheet layout sorted rhymes into per-type buckets; Chapter 4's does
  not.** The file gave every core word five labelled rows — perfect, family,
  additive/subtractive, assonance, consonance. The chapter's own worksheet is
  ten numbered core words, each heading ONE undifferentiated column with every
  rhyme type mixed together. The mixing is the point: a single field is scanned
  and compared on meaning, where five labelled rows turn one choice into five
  sub-choices and invite filling each to a quota — the opposite of generating a
  surplus in order to reject most of it. The per-type SEARCH still runs — each
  type is a different lookup and skipping one loses candidates — but its results
  are recorded together; type matters again only when placing a survivor, which
  is `rhyme-strategy.md`'s job.
- **The template carried keep/maybe/reject and notes fields the chapter's
  worksheet does not have.** Its only annotation is parentheses, doing two jobs:
  holding an alternate word behind a first choice that shares its vowel
  (`freeze (wheel, shield)`), and marking an optional morpheme that records two
  candidates in one entry (`(re)born`, `guarantee(s)`). Rejection happens by not
  writing the word down. The workflow step that told the model to mark each word
  now matches the page it writes on.

## [0.7.3]

A source-fidelity pass over `prosody.md` against *Writing Better Lyrics* (2009)
Chapters 18-19, read in full including both figures. Paraphrase only; no chapter
prose, example writes, or student work reaches this public repository.

### Fixed

- **`XAAA` was described as doing the opposite of what it does.** The file
  claimed "stronger end pressure after an opening unmatched line"; Chapter 19
  says the structure floats rather than pushes, and locates the instability in
  the odd number of `A`s — line count and matched-element count disagreeing —
  not in the opening unmatched line. Line lengths modulate the effect, and the
  file now says so.
- **`ABCBB`'s spotlight was attributed to the wrong line length.** The long `C`
  weakens line four's closure and dims line five with it; it is the *shortened*
  `C` that lets line four close and brightens the spotlight on line five.
- **`AABA` was reduced to "points forward toward another `AB`."** The `B` line
  asks for another `B`, not another pair, and the section balances at the
  opening couplet so there is no push before it. Line four mildly fools that
  expectation, leaving a small spotlight on the last line.
- **The rhyme-type scale collapsed two of its five tiers.** Additive/subtractive
  and assonance are separate rungs between family and consonance, not a pair.

### Added

- **The two-line stability ladder, and the rule it yields.** Four rungs, not
  two: matched length with rhyme, matched length without rhyme, rhymed but
  unmatched, neither. The middle pair is the point — matched length without
  rhyme outranks rhyme without matched length, so **line length is a stronger
  motion creator than rhyme.** Nothing in the plugin carried this. It is a
  tiebreak between those two elements specifically — the ladder says nothing
  about line length against rhythm or line count, where the biggest-mismatch
  rule still decides.
- **Closure extended past common meter.** `meter.md` defines deceptive and
  unexpected closure and keeps that ownership; Chapter 19 applies the same
  expectation test to any section shape, so `prosody.md` carries only the delta
  — unexpected closure as the mechanic organizing the five-line
  one-matching-element group, and sections firing both effects in either order.
  `stable-unstable-meta.md`, whose Closure row sorts by the terms without
  defining them, now points at the definition.
- **A five-line section ending in an unmatched line is the most unstable of its
  group** — a flat rule the file had replaced with "depends on how late the
  matching material arrives."
- **Which line is the targeting slot.** An unmatched line's end sound points
  into the next section: aim it at a vowel inside the oncoming title for a sonic
  boost, at the title's end rhyme for a harder resolution, or waste it. `hook.md`
  owns the hook-side strategy; this is the structural question of which line
  carries it.
- **The order in which structure becomes audible** — rhythm, line length, rhyme
  structure, number of lines, rhyme type. This is what the listener receives,
  which is why expectations exist by a given line; it is distinct from the
  Analysis workflow's marking order, and the file now says so rather than
  leaving two orders to be read as one instruction.
- **`response-filter` §3 gains two boxes.** Chapter 19's two generation-time
  rules bind rather than sit in a research file: line length is checked before a
  finding prescribes a rhyme change, and a closure called deceptive must name
  the prediction the section actually built.
- **The flat-song diagnostic**, deferred from 0.7.1's Chapter 15 read pending
  this chapter. Chapter 19 states it in motion terms, so `prosody.md` is its
  home: a good line landing flat is a structure problem, not an inspiration
  problem.

## [0.7.2]

A source-fidelity pass over `meter.md` against *Writing Better Lyrics* (2009)
Chapters 14-17, read in full including the chapters' page-scan figures, plus
one binding fix in `meter-prosody`. Paraphrase only; no chapter prose, example
writes, or student work reaches this public repository.

### Fixed

- **`meter-prosody`'s mandatory pre-flight ran the wrong filter.** It routed to
  `response-filter` §6 Form, whose boxes decide song shape — chorus versus
  refrain, whether a bridge is needed — while the skill's own emission boundary
  forbids it from making that call. The skill was required to check boxes it is
  not allowed to act on, and nothing gated the output it actually emits. It now
  routes to §3 Critique, the filter for findings delivered on a draft.
- **Chapter 16's nine couplet / common-meter models were transcribed wrong.** The
  exercise listed eight of the nine, dropped `abaa` entirely, corrupted two
  rhyme schemes (`ababaccc` for `aaabcccb`, `abacccc` for `ababcccc`), stripped
  every stress count, and labelled the whole set four-stress when five of the
  nine set a three-stress line against four-stress neighbours. The models now
  carry both dimensions in their own table.
- **The Structural Pentad was defined two incompatible ways in one file.** One
  section listed the Five Compositional Elements (number of lines, length of
  lines, rhythm, rhyme scheme, rhyme type) under the Pentad's name, while the
  file's two other definitions — and `five-compositional-elements.md` — name
  balance, pace, flow, closure, and type of closure. Corrected, with the
  distinction between the two frameworks stated where the confusion occurred.
  The same section's claim that `stable-unstable-meta.md` applies the Pentad
  across domains was also wrong: that file carries per-domain stability
  criteria of its own.
- **The eight-line couplet escape omitted its line lengths.** Its fourth and
  eighth lines are shorter — three stresses — not merely unrhymed and answered;
  an unrhymed line of matched length does not open the same IOU.

### Added

- **`response-filter` §3 gains two boxes.** Line length must be claimed in
  stressed syllables, with no stress map meaning no length claim; and every
  position the structure marks must be named along with the content sitting
  there, so a spotlight over filler reads as a finding rather than a flourish.
- **The extension-inside-line-four move lights two positions, not one** — the
  third stressed syllable, where the expected rhyme failed to arrive, and the
  fourth, which protrudes past the promised end. Its insertion is also two
  syllables, one unstressed and one stressed.
- **Closure defeats rhyme independently of distance.** A rhyme whose partner
  sits two lines away can still read as unrhymed once an intervening unit has
  closed and the ear has stopped listening back across the seam.
- **Composite destabilizing.** Several destabilizers can fire in one section at
  once and compound — odd line count, odd rhyme scheme, a first-use short line,
  and a section outrunning the bar count the song had established. Bar-count
  overrun is a device in its own right and the one most easily missed on the
  page.

## [0.7.1]

### Fixed

- **Title-type taxonomy reconciled with `hook.md`.** `research/idea-to-title.md`,
  `research/title-game.md`, and `templates/idea-to-title-prompt.md` each cited `hook.md`'s seven
  title types while listing a different set; all three now carry hook.md's One-word / Place-name /
  Person-name / Color-or-sensory / Comparative / Word-play / Sonic-bonding, completing the
  reconciliation 0.7.0 started in `research/response-filter.md`. A maintainer holding Pattison's
  source can re-split the taxonomy — adding the displaced Statement / Question / Command /
  Phrase-from-lyric / Image-as-noun / Idiom-recontextualized / Name set to `hook.md` under its own
  heading and repointing those citations there — if it proves to be a genuine second framework.

### Changed

- **Pre-flight filter narration may live in reasoning.** All eight craft skills' mandatory
  pre-flight blocks now read "(aloud or in reasoning)", and `research/response-filter.md`'s no-op
  confirmation drops its visible-response mandate. The gate must still provably run.
- **`/songwriting:suno clean` states what changed and why in its response** rather than showing a
  diff in reasoning.
- Book-citation guidance in `research/book-references.md` reworded from an ALL-CAPS prohibition to
  a plain directive.

## [0.7.0]

Two changes in one release: a fix for the plugin's central failure — craft
disciplines that load into context and then fail to bind at generation time —
and a source-fidelity pass over three context files. Paraphrase only; no
chapter prose, example writes, or student work reaches this public repository.

### Added — the binding fix

Piloting the plugin end-to-end on a song established that loading a context
file does not make its discipline govern generation. A file stating that
choruses tell was in context two turns before three choruses were emitted that
show; a filter's boxes were listed as passed while the emitted lines failed
them. Reading a rule and obeying it at generation time are separate problems,
and only the first was addressed. Three changes attack the second:

- **`object-writer` agent** — performs the object write itself rather than
  prompting a human, with the discipline in its own system prompt rather than
  in a file it consults. Dispatched blind, one per seed, deliberately denied
  the song, the draft, and the other writers' output, because same-seed
  divergence depends on isolation. Writes its result to a file and returns a
  path plus a seven-channel sense inventory quoting its own phrases, with thin
  channels reported rather than padded. Reached through the new
  `/songwriting:object-writing generate` action.

  This shape was validated during the pilot: agents carrying the discipline in
  their prompts produced materially better output than the main thread did with
  the same files loaded, including one that graded its own organic channel thin
  and refused to pad it. The file-not-message return is also empirical — long
  creative text proved unreliable over the agent return channel.

- **Emission boundaries on every craft skill.** Each skill now states what it
  must NOT emit and which skill owns that output. `song-form` does not write
  lines; `rhyme` does not write the line its rhyme lands in; `meter-prosody`
  measures but does not rewrite; `object-writing` produces ore, not lines. In
  the pilot the structural skill wrote three chorus drafts while its own
  routing said rhyme work belonged elsewhere.

- **A hard input gate on `co-write`,** the one skill that legitimately emits
  lines. Its gate is satisfied by artifacts that exist — a menu of rhyme
  candidates visible in the response, object-writing output at a named path, a
  marked stress map — not by naming boxes as passed. A skip stays valid and
  stays named; a box claimed as passed with no artifact behind it is a failed
  box.

### Added — metaphor as a first-class skill

`/songwriting:metaphor` with generative actions (`collide`, `recipe`, `keys`,
`types`, `simile`, `diagnose`), taking object-writing output as its input. The
underlying `metaphor.md` was verified faithful against *Writing Better Lyrics*
(2009) Chapter 3 and is unchanged — the defect was placement. 755 lines of
accurate method were reachable only as one action inside a skill about a
different discipline, and across an entire pilot song it never fired once,
despite that song containing no metaphor at all.

Two corrections from the chapter now sit where generation happens rather than
only in the reference: a metaphor must be literally false, since identity
without conflict is definition; and noun+verb collisions outperform
adjective+noun, because verbs drive a line — the correction that matters most,
given that the default reach is always for an adjective.

### Changed (breaking)

- **`/songwriting:object-writing metaphor` and `metaphor-recipe` are removed.**
  Both route to `/songwriting:metaphor` (`collide` and `recipe`). Cliché repair
  stays in `object-writing`, since its taxonomy covers stale phrasing beyond
  metaphor.

### Fixed — source fidelity

Six context files adjudicated against the full text of the chapter each claims
to distill, rather than against the distillation. Chapters 1, 3, 6, 7, 8, 9, 10,
11, 12, and 13 of *Writing Better Lyrics* (2009) read in full.

- **The deceptive cadence was absent from all 49 context files.** *Writing
  Better Lyrics* (2009) Chapter 13 names the move: a chorus opens `aba`, the ear
  leans toward a resolving `abab` close, and the fourth line repeats the title
  instead. It repeats the title, spotlights it through the structural surprise,
  and resolves the section *less securely* than the expected rhyme would have —
  and that third effect is the craft point. The chapter's example is a character
  asking for something she has not been given; full resolution would sound as
  though she already had it. Now in `hook.md` with the match-the-cadence-to-the-
  question rule and its counter-case: a section that resolves or answers wants
  the expected rhyme, and withholding it there fights the meaning.

- **`point-of-view.md`'s dialogue coverage gains three mechanics.** The duet
  test is the chorus, not the conversation — if the repeated section is one
  character's plea, the other cannot sing it and the song is not a duet however
  evenly the dialogue is split. First-person dialogue whose story belongs to the
  other character has two exits rather than one: move to third person, or keep
  first person and write the narrator a closing insight that earns the
  retelling. And Chapter 13's structural sequence is now stated as the
  three-stage setup it is — balanced verse, off-balance three-line transitional
  bridge, withheld chorus rhyme — rather than compressed to a pointer, because
  in quoted dialogue the structure decides which character's words the section
  is actually about.

- **`repetition.md`'s hidden-question mechanic was inverted.** *Writing Better
  Lyrics* (2009) Chapter 6 deletes the **interrogative pronoun** and keeps the
  auxiliary, which is what leaves the fragment a question — "Who do you love?"
  becomes "Do you love?". Four of the file's seven table rows deleted the
  auxiliary instead ("Can you remember?" → "You remember?"), which destroys the
  effect rather than producing it. The rewritten table also states the semantic
  payoff the original omitted: the full question presupposes the action and asks
  for its object, while the fragment asks whether the action happens at all.

  Two adjacent corrections in the same section: with past- or future-tense
  verbs the command hides inside the **infinitive phrase**, not the main verb,
  and the isolation can be staged twice, each pass landing harder; and Chapter
  6 frames the whole technique's payoff as the **change of sentence type** —
  statement to question, statement to command — so a fragment that repeats
  without changing type is an echo, not productive repetition.

- **`repetition.md` gains eight mechanics** present in Chapters 6 and 9 and
  absent from the distillation: stagnant boxes *lose* weight rather than merely
  flattening, because boredom amplifies; polished language cannot fix a
  development problem, which fixes the diagnostic order; the per-line box-weight
  test, where one chorus line is read after each verse (Chapter 6's own example
  moves an image from observer to witness to prophet on identical words); the
  drafting constraint that every chorus line must be *able* to gain weight; a
  box may span more than one section, so boxes are counted by idea movement, not
  section count; Box 3 as the song's *why*; both named formulas carrying
  Chapter 6's own warning that a formula can take the freshness out of writing,
  making them repairs rather than defaults; and thinking in boxes from the
  moment an idea arrives as the *prevention* for second-verse hell, where
  reordering is only the rescue.

  Also corrected: "verses show, chorus tells" now carries the instruction
  Chapter 9 attaches to it — keep the verses specific and interesting — and
  states that neutral means grammatically neutral, not vague, since the
  chapter's own demonstration chorus is built from concrete images while
  committing to no tense and no pronoun. Plus the working consequence of a
  chorus being many people singing together: change the words and no one can
  sing along, which is why the fix for a stagnant chorus is always to develop
  the verses.

- **`box-model.md` defined "travelogue" three incompatible ways.** *Writing
  Better Lyrics* (2009) Chapter 8 defines travelogue as verses with no natural
  relationship to each other, linked only through the title or chorus, so the
  boxes accumulate no weight. Verses that do the same job or project the same
  color are the OPPOSITE failure — Chapter 7's colored-spotlight problem, where
  the chain is intact and the repainting is missing — and Chapter 8 closes by
  naming both poles explicitly. The file now separates the two, gives each its
  own test, and states that equal box weight is a symptom of travelogue rather
  than a synonym for it. The prior conflation prescribed the wrong fix:
  division-of-labor shifts for a lyric that needed a causal chain.

### Added

- **`object-writing.md` restores six mechanics present in *Writing Better
  Lyrics* (2009) Chapter 1 but lost in distillation.** The chapter's own
  instruction to follow sensory association was carried without the mechanism
  that produces it, which yields static scene description instead of a dive.
  Added: the pivot chain (each image handing off through a sense channel, with
  a worked example and a numbering diagnostic); the seven-channel sense
  inventory as an acceptance test quoting the write's own phrases, with thin
  channels reported rather than padded; specificity calibration set at the
  chapter's actual density rather than a generic-to-less-generic swap;
  invention explicitly licensed, since the chapter holds that a song is not
  autobiography and truth outranks reality; the group model's same-seed
  divergence and its round-over-round escalating bar; and perspective writes
  run inside a character's senses rather than the writer's.

- **`response-filter.md` §2 gains an unintended-implication box.** A line could
  pass every existing box — sense-bound, specific noun, strong verb, no cliché,
  consistent POV — and still assign a character a motive the writer never
  chose. The check is grounded in Chapter 1's own account of why sense-bound
  language works: the listener fills the writer's words with their own
  associations, and that mechanism is not selective, so a more concrete line
  carries more unintended implication rather than less. Paired with a
  "nothing without its purpose" box carrying Chapter 10's invocation of
  Ibsen's rule about the gun in Act I.

- **`song-form`'s stagnation eval asserted the defect this release fixes.** Its
  prompt is the same-color case verbatim — a second verse repeating the first,
  same scene, same speaker, same time — while its expectations required the
  model to name a *travelogue*. A model following the corrected `box-model.md`
  would have failed the eval, and a model passing it would reproduce the
  conflation. Now expects the same-color diagnosis and explicitly forbids the
  travelogue label, with a new companion case covering the genuine travelogue so
  the two failures are pinned apart rather than merely relabeled.

## [0.6.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.6.0]

### Changed (breaking)

- **`diagnosis` and `daily-practice` skills renamed** (fleet conformance wave: naming grammar).
  `/songwriting:diagnosis` becomes `/songwriting:diagnose`, and `/songwriting:daily-practice` becomes
  `/songwriting:practice`; both skills' behavior, actions, and shared reference corpus are unchanged.
  The new names follow the verb skill-naming grammar. The craft term *diagnosis* and the *daily
  practice* curriculum keep their names in prose — only the skill invocation tokens changed. Update
  saved invocations and any cross-skill routing to the new tokens.

## [0.5.0]

### Changed

- **`setup` skill refactored onto the uniform check/apply contract** (fleet conformance wave).
  `/songwriting:setup` replaces the interactive-interview shape with `check` (default, read-only:
  inventories the tracked template overrides under `songwriting/templates/pat-pattison/`, flags
  byte-identical overrides, and reports the effective artifact layout) and `apply` (non-interactive:
  `apply scaffold <name>...` copies a bundled default into an override, `apply remove <name>...`
  clears one). The two-surfaces model, the override-freeze cost, the copy-all-sixteen anti-pattern
  warning, and the never-edit-consumer-`CLAUDE.md` boundary are unchanged. Overrides remain the only
  thing setup writes.

## [0.4.1]

### Changed

- **Suno fact tables re-verified 2026-07-18 and corrected** (fleet conformance
  wave: freshness riders). Lyrics limit corrected to a 5,000-character hard cap
  on v4.5/v5/v5.5 (~3,000 stays as the quality sweet spot; 3,000 was the
  v4-era cap — the May consensus position flipped), title to ~100 characters,
  and the tier matrix's Suno Studio row to Premier-exclusive. Confirmed tables
  (Voices, release dates) carry dated riders with official links; unverifiable
  rows keep their hedges undated; upload limits corrected to the current
  pricing page (Free up to 8 min, Pro/Premier up to 30 min — the 60s/120s and
  8-min figures were both stale). All `help.suno.com` source links fixed to
  the working `/en/articles/` form. Character limits remain third-party-tester
  sourced — Suno publishes no official field limits — and the riders say so.

## [0.4.0]

### Added

- **Behavioral evals restored, adapted to the multi-skill split.** The `pat-pattison` mega-skill's
  full eval suite (13 cases) shipped zero replacement coverage when it decomposed in 0.2.0. All 13
  cases are ported forward, each adapted to the concern skill and action that now owns its behavior:
  `workflow` (brainstorm, idea, fragment — 3 cases), `diagnosis` (demo, audit, variations — 3 cases),
  `rhyme` (rhyme, datamuse — 2 cases), `song-form` (box-model, bridge — 2 cases), `co-write`
  (title-game, co-write — 2 cases), and `object-writing` (metaphor-recipe — 1 case). No case was
  dropped — every behavior the original suite exercised still exists in the split. Prompts and
  expectations are updated to the plugin's `/songwriting:<skill> <action>` invocation form and
  current `SKILL.md` contracts.

## [0.3.0]

### Added

- **`setup` skill — re-runnable configuration action.** `/songwriting:setup` scaffolds project-level
  prompt-template overrides under `songwriting/templates/pat-pattison/` from the bundled defaults and
  confirms where craft artifacts land, satisfying the extensibility contract's "every configurable
  plugin ships a setup action". It reads existing overrides first (idempotent), scaffolds only the
  templates the consumer intends to customize (an override freezes that template against future
  plugin improvements), offers to remove byte-identical overrides, and reads — never writes — the
  consumer's own `CLAUDE.md` layout convention. Additive: no existing invocation changes.

## [0.2.0]

### Changed (breaking)

- **Decomposed the `pat-pattison` mega-skill by concern.** The single lyric-craft skill is replaced
  by focused concern skills: `workflow`, `rhyme`, `object-writing`, `meter-prosody`, `song-form`,
  `co-write`, `diagnosis`, and `daily-practice`. Each is a thin router over the shared reference
  corpus and runs the applicable response-filter section as its pre-flight. The `suno` skill is
  unchanged.
  - **Invocation change:** `/songwriting:pat-pattison <action>` is removed. Use the concern skill
    that owns the action — e.g. `/songwriting:rhyme`, `/songwriting:meter-prosody meter`,
    `/songwriting:diagnosis audit`. `/songwriting:workflow` is the start-here situation router and
    carries the full cross-skill routing index and Quick Decision Guide.
- **Reference content is preserved, not lost.** All 48 research files, 16 templates, the Datamuse
  script, and the response filter moved verbatim to `context/pat-pattison/`, keeping every
  intra-corpus link intact.

### Design decision — concern-as-skill, author-as-context

The decomposition separates two independent axes: **concern** (the craft topic → the skill you
invoke) and **author/method** (whose opinionated technique → a content namespace). Pat Pattison's
full method now lives once under `context/pat-pattison/`; the concern skills are author-neutral
interfaces that load it. A future author's method for the same concern plugs in at
`context/<author>/` without modifying the concern skills (open for extension, closed for
modification). This is why the corpus is namespaced by author rather than sitting in a plain
`context/` pool.

## [0.1.0]

- Initial release: `pat-pattison` lyric-craft skill (all four books plus Berklee/Coursera materials,
  action router, mandatory response filter) and `suno` Suno v5.5 prompt-engineering skill.
