# Changelog

All notable changes to the `songwriting` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [1.0.1]

**Axis 2 closes at 226 of 226.** The last 21 fine-grained units — *Essential
Guide to Rhyming* (2014) front matter (spine 0-13) and back matter (spine
132-138) — are audited. No unit at any granularity remains unread in any of the
four books. Axis 1 stays 44 of 44.

The larger part of this release is a **refutation pass over unverified work**.
An example-level sweep of all four books had been committed to this branch by a
run that terminated on a content-filter error *before writing any receipt*, so
none of it was audited. Eight fresh agents, one exclusive write-set each, were
dispatched to disprove it rather than bless it.

### Fixed — 20 defects the refutation pass found

Counts summed from the eight receipt headers, not estimated: **49 CONFIRMED,
20 REFUTED, 6 INCOMPLETE-RESTORATION, 0 UNPROVABLE.** Some hunks are both
refuted and incomplete, so those two columns overlap.

Every defect is a fidelity failure, not an invention. The pattern from previous
sessions holds: the real risks are truncation, dropped items and over-claiming.

- **Truncation.** `rhyme-fundamentals.md` presented the Introduction's first and
  third sentences as consecutive and dropped the one between them; its closing
  quotation stopped three sentences early. `rhyme-strategy.md` dropped a colon
  and its three-line example, compressed a four-line reversal, and reduced a
  worked case to two rhyme pairs. `verse-development.md` ended two set-ups on a
  colon and replaced the printed examples with cross-references.
- **Typography standing in for verbatim text.** Curly quotation marks normalized
  to straight, and an italic span covering a complete refrain phrase dropped, in
  `song-forms.md`; punctuation, capitalization and apostrophe typography altered
  inside two quoted passages in `rhyme-sonic-bonding.md`.
- **Over-claiming.** `form.md`'s own figure inventory claimed 21 substantive
  transcriptions where the true count is 20, and asserted two choruses share
  wording when they share a four-phrase `x a x a` structure and open
  differently. A scaffolding note said four exercise bodies were already
  verbatim while two still had formatting defects. A coaching gloss turned Pat's
  qualified claim that most work moves into the writer's head into an absolute
  claim that worksheets become unnecessary.
- **Citation-format violations** against the plugin's own rule, in eight places.

Deliberate repetitions were left intact wherever Pat prints a passage twice as
pedagogy — the false-positive trap that would have destroyed correct text.

### Fixed — Suno platform drift

- **The highest-volume mis-tiering in the skill.** One line stamped "Creative
  Slider behavior" as HIGH confidence and thereby certified roughly thirteen
  unsourced numbers as officially confirmed. HIGH now covers only slider names
  and qualitative endpoints; every numeric setting is community-empirical.
- **Audio Influence for an active Voice: raise it.** The 25-30% figure is
  removed along with its "contradicts initial Suno docs" framing, which was
  backwards — it contradicts *current* docs. No threshold, including `>=70%`,
  is first-party; Suno publishes no number.
- The unsourced v4.5-metatag-breakage claim and the invented `[Vocalist:
  Female]` form are deleted; `[Male Vocal]` / `[Female Vocal]` are kept.
  `[Synth Solo]` no longer appears as non-standard ten lines above the list
  that calls it recognized.
- **Cover/harmony added with its evidence bounds attached.** The per-element
  preserve table, the documented-absence answer on chord control, and the
  re-record-then-Cover workaround. That cluster reached **zero community
  sources** and Reddit was unreachable, so "Suno documents no way to do this"
  is stated explicitly as not meaning "this cannot be done", and the section is
  flagged for a community-source re-run.
- Reuse corrected to text-field reuse with no slider; "harmonic seed" removed.

### Verified rather than assumed

- The **shipped invocation path** was tested cold for the first time. Routing
  resolves, `${CLAUDE_PLUGIN_ROOT}` / `${CLAUDE_PROJECT_DIR}` expand correctly,
  the response-filter pre-flight fires ahead of output, and **all 761 relative
  links and 38 heading fragments resolve**. Caveat: the plugin is served from
  the repo checkout, so this exercised the branch content, not the published
  1.0.0 tarball.
- Two `genre-taxonomy.md` pointers an earlier commit claimed to have repaired
  did not resolve; they were placeholder and brace-expression forms that
  ordinary link checking misses. Now expanded to concrete files.
- Pat's italic on `you` — "the hardest thing you will ever do is to write as
  well as *you* can" — restored from the Afterword page scan. The 2014 text
  layer strips italics and wraps each word in its own span, so only the scan
  could settle it.

### Known, and deliberately not changed

- **Suno D2 is unresolved and awaits a maintainer decision.** The skill teaches
  a single varied 90-120s voice-clone clip in one file and three separate clips
  in two others. No external source resolves it; agents were forbidden to pick.
- Inline changelog prose ("An earlier revision of this file claimed…") remains
  in nine runtime context files. It is accurate and is this project's main
  defense against fabrications regrowing, but it belongs in a receipt.
- **`hook.md` lyric enrichment was attempted and DROPPED.** The agent produced
  141 lines, but it transcribed figures by building an **OCR pipeline** and then
  "correcting OCR errors" — including inserting a missing apostrophe — instead
  of rendering each figure and reading it. Roughly half of this project's
  quote-checker misses are already extraction artifacts; OCR adds a new artifact
  source, and repairing its output by inference is the fabrication risk the
  whole audit exists to prevent. The work is discarded unverified rather than
  shipped. `hook.md` is unchanged in this release.

## [1.0.0]

**Chapter coverage was complete at 0.9.0; file coverage was not.** This release
audits the five files built from chapters closed in earlier sessions, reads the
three non-book web sources that eight sessions had treated as unopenable, and —
for the first time in ten sessions — **tests whether the plugin's output is any
good.**

Scoreboard, computed from the ledger and unchanged by this release because the
work was file-level, not chapter-level: **Axis 1 — formally audited, 44 of 44
units (100%). Axis 2 — fine-grained, 205 of 226 (91%).** The 21 outstanding
fine-grained units remain *Essential Guide to Rhyming* (2014) front matter
(spine 0-13) and back matter (spine 132-138) — TOC, preface, afterword, index.
No craft chapter is unaudited in any of the four books.

### Added — the output test, and what it found

- **The lines are good, and the reason matters.** Running the craft skills on a
  real brief produced usable verses in common meter and a chorus using Paradigm
  Three's deceptive closure to spotlight the title. The `object-writer` agent is
  the strongest component: dispatched blind on the seed "an extension cord",
  knowing nothing of the brief, it returned "seven turns, always seven, he
  counted them out loud" for a song about a dead father. The blind dispatch is
  what produced that, and both writers graded a thin sense channel honestly
  rather than padding it.
- **The quality is contingent on the response filter actually running.** Every
  good line survived because a specific §2 box rejected a worse one; drafting
  without naming boxes produced the generic default the filter exists to catch.
  **`response-filter.md` is therefore the highest-leverage file in the plugin**,
  and the filter is self-administered with no enforcement.
- Caveat recorded rather than glossed: the installed plugin was 0.8.3 while this
  branch was 0.9.0, so the *content* was tested by executing the skill bodies
  directly. **The shipped invocation path is still untested end to end.**

### Fixed — two "duplications" that were not, and one that was

- **`phrasing.md` and `meter.md` were FALSE POSITIVES.** Pat prints the Steely
  Dan verse at eight phrases, then pulls one out to show seven, then cuts to
  four — that is his pedagogy. `meter.md`'s two "Mary Had a Little Lamb" blocks
  differ in line four: a three-stress close for Paradigm One against a
  four-stress overshoot for Paradigm Three. **Folding either would have
  destroyed correct Pat text.** Both left alone.
- **`song-forms.md` was the only genuine one** — a whole "Third-system risk"
  section restating Chapter 23's worked lyric and Pat's three numbered Options.
  Folded to a cross-reference; the surviving section verified to lose nothing.

### Fixed — the 1991 figure trap, caught live again

`"She sold the fleece to pay the rent"` returns **zero hits** in the 1991 text
layer, wrap-safe and by fragment. It is **genuinely printed** in figure
`image_rsrc30F` with "the rent" in italics. That book argues in figures and its
text layer under-reports; every cut in `meter.md` was checked against a rendered
scan first. A verification pass rendered **all 45 Chapter 3 figures** and
confirmed none prints a mood, a section label, or a "best for" line — so the
three unsourced comparison rows and the "Teaching move" line were cut correctly.

### Fixed — file-level audits

- **`cliche.md`** — the cliché-phrase list shipped as "a representative slice,
  in his grouping" and was neither: **43 of Pat's 101 printed cells were
  missing, and surviving rows were stitched together from different printed
  rows.** The complete 34-row table is restored from the raw XHTML and verified
  cell-for-cell, including the duplicate `losing sleep` that Pat really prints
  twice.
- **`rhyme-strategy.md`** — the two "Decision matrix" sections were **not**
  duplicates but different subjects; one had Pat's family/assonance pairing
  **inverted**. Nine Chapter 9 pairings re-verified in the chapter's own order.
  The two Strategy 1/2/3 treatments *were* genuine duplication and are merged.
- **`rhyme-worksheets.md`** — a thirteen-slot seed box was attributed to
  Exercise 7.2; the page-75 scan shows it inside the Exercise 7.1 grid, between
  `6. risk` and `7. chance`. A column-order extraction artifact. Also fixed:
  `flirt / church` mislabelled consonance when Pat's own definition requires
  differing vowels, and a claim that all eleven seeds came from his page-20
  sketch when only three do.
- **`object-writing.md`** — 2009 Chapter 2 prints no exercise at all; an
  invented count was presented under its provenance. Rusty's collar moves down
  **two** lines, not one.

### Fixed — non-book sources, all three READ for the first time

- **patpattison.com "Lyric and Melodic Phrases"** — the "maximum meaning" quote
  is real and had been truncated. Its taxonomy of fixes is **Pat's own and has
  four options**, not three; a prior pass had demoted it as plugin-authored, and
  dropping his fourth ("Keep it the way it is, since no one listens to lyrics
  anyway") is what made the list look invented.
- **patpattison.com "The Art of Phrasing"** — **`front-heavy` / `back-heavy` are
  Pat's own coinage**, defined on that page, not plugin shorthand. So is
  "Phrasing has the power to create emotion. It's the body language of your
  song." Both had been wrongly marked. **"Not in the four books" and "not Pat's" are
  different claims** — cite the column, never a chapter.
- **American Songwriter "Motion Creates E-Motion"** — carries no four-controller
  framework and never mentions line length, so the "live unresolved conflict"
  with *Songwriting Without Boundaries* (2011) Challenge 4, Day 13 **does not
  exist.** Recorded as incomplete, not contradicted.

### Fixed — third-party lyric restorations (all Class A defects cleared)

All five `LYRIC-HANDOFF` markers in `form.md` are resolved — every dangling
set-up now has its text under it: the four "IT WAS A VERY GOOD YEAR" verses in
Pat's order, the "Years" chorus and its nine-line verse, both Song Systems from
figures `image_rsrc32F` / `32G`, and the deceptive-closure rhyme figures.
Scansion was read off rendered figures rather than re-derived, and **Pat's own
"thirty-five" / "thirty five" inconsistency is preserved as printed.**

### Fixed — vocabulary and the agent contract

- **`central emotion` (0 corpus hits) replaced with Pat's real phrase**, "the
  central intent, idea, and emotion of the work" (*Writing Better Lyrics*
  (2009), Chapter 18), across nine files. It truncated a real three-part phrase,
  which is why quote sweeps kept missing it.
- `tone of voice` (0 hits, and not located in any Pat column either) registered
  as plugin shorthand in `book-references.md`.
- **The `object-writer` agent's frontmatter promised a return shape its own
  output contract forbids.** Corrected to match: path, seven graded channels,
  one sentence.
- Audit-process vocabulary had leaked into shipped content — a reader hitting
  "see LYRIC-HANDOFF" had no way to know what that meant. Removed.

### Fixed — Suno platform drift (partial)

The two first-party-contradicted tier rows are corrected: **Free has no stem
separation at all** (the "2-track stems: Free ✓" row was false), and Split from
Mix / Auto Split / Advanced Split are three **modes**, not track counts. Voices
stays Pro / Premier; free plans got a **trial** on 7 August 2026, with an
unresolved web-versus-mobile caveat recorded rather than guessed — a trial is
not all-tier entitlement, and the plugin no longer describes it as one. **The remaining Suno remediation items are not
done** — see the audit's own ordering in `.work/songwriting-plugin-pilot/`.

## [0.9.0]

**All four Pat Pattison books are now formally audited — 44 of 44 units.** This
release closes the remaining 15: *Essential Guide to Lyric Form and Structure*
(1991) Chapters 5 and 7, *Essential Guide to Rhyming* (2014) Chapters 1-9, and
*Songwriting Without Boundaries* (2011) Challenges 1-4. **127 fabrications were
removed and 283 passages restored verbatim.**

### Fixed — charts and figures the EPUB text layer corrupts

- **Pat's Vowel Triangle was wrong in both legs**, in two files. The figure is
  printed as a **V with the apex `ä (papa)` at the bottom**; the text layer
  hoists `ä` to the top and transposes vowels on each leg. Corrected against the
  page scan to tongue leg `ä → ă (cat) → ĕ (end) → ĭ (it) → ē (me)` and lip leg
  `ä → ŭ (up) → ŏ (hot) → oo (foot) → ū (too)`. **This is load-bearing:** family
  assonance is defined as *one step* along a leg, so a transposition changes
  which pairs count as adjacent. `rhyme-generation.md` had it worse — `ŭ (up)`
  on the wrong leg entirely and `ă (cat)` missing. Both files now carry an
  in-file warning against re-deriving it from text.
- **The consonant chart (2014 Chapter 5) emits column-major as garbage.**
  Transcribed from the scan. Nasals are a *single* row (all voiced), not a
  voiced/unvoiced split.
- **Two answer keys existed only as images** and are restored — 2014 Exercise
  8.1 (printed rotated 180°) and Exercise 8.3 item 1, which had been silently
  dropped.
<!-- spellchecker:off -->
- **1991 Chapter 7's scansion figures** (12 of them) transcribed from the page
  images. Figure `34C` carries a genuine printing discrepancy — its stress marks
  show three stresses where its DUM-da row shows four — **reproduced as printed,
  not corrected.**
<!-- spellchecker:on -->

### Fixed — invented scaffolding, the dominant defect class

- **127 fabrications removed across 30 files.** The recurring shapes: `Use when:`
  lists, bullet "tests", `- [ ]` checklists, named axes, "Revision workflow"
  step-lists, decision matrices, and round-number thresholds.
- **Counts and category lists were the most reliable tell.** Corrected: a
  five-item metaphor taxonomy where **Pat's count is three**; "Pat's four focus
  questions" where he prints **six**; a seven-name transitional-bridge alias list
  where the figure prints **six**; a seven-row clause table where he names
  **five**; a four-bullet hot-spot list where he prints **three** levels; "six
  rhyme types" under a heading whose printed scale has **five**.
- **Round-number thresholds were invented without exception** — "3-5
  candidates", "over 30 minutes", "5-15 per seed word", "removes ~30% of
  AI-generated rhyme lists". `minutes` appears **zero times** in the entire 2014
  book.
- **A table that inverted its chapter's argument.** `rhyme-generation.md`
  assigned each rhyme tier one fixed use-case; 2014 Chapter 9 argues every
  effect is **position-conditional** — the same family rhyme lightens a push in
  the dominant slot and softens a landing in the tonic slot. Replaced with Pat's
  seven printed dominant×tonic substitutions.
- **An entire masculine/feminine/mosaic example table** whose every pair
  (`time/rhyme`, `dreary/weary`, `going/showing`, `silence/find us`) returns zero
  hits in **both** the 2014 and 1991 books while cited to "2014, Chapter 1".
- **`metaphor.md`'s self-declared "Restoration blocked" hole is closed** — all
  six of Pat's printed Day 10 answers restored verbatim.
- **A misattribution to Pat of someone else's term.** "Destination writing" is
  **Andrea Stolpe's**; Pat credits her by name and book title. The invented
  "8-9 minutes / 1-2 minutes" form attached to it is gone.

### Fixed — quotes

- **A fabrication recorded as fixed in 0.8.6 was still live.** `"Craft prepares
  you to be creative."` was corrected in `rhyme-types.md` and **survived in
  `exercises.md`** with its citation intact. Pat's real line is "Craft prepares
  **him** to be immensely creative with his shots". A fix in one file is not
  proof the invention is gone from the corpus.
- **A paraphrase was standing in as a verbatim quote.** "Tools, not rules." in
  that word order appears in **none** of the four books — it is the *column
  title*. Pat's printed line is "There are no rules, only tools."
  (*Writing Better Lyrics* (2009), Chapter 18), and again as "there are no
  rules. Only tools." (*Essential Guide to Rhyming* (2014), Chapter 4).
- **"One focused finding outweighs ten scattered notes" was invented** (zero
  corpus hits) and was labelled **"Pat's rule"** in two files. Retained as
  plugin-authored coaching posture with the attribution removed.
- **`state / vary / withhold / deliver`** — an invented four-stage scaffold
  carrying a blockquote falsely attributed to 1991 Chapter 7. Removed from
  `hook.md` and from its recurrence in `beyond-books.md`.
- **An invented "Shelley principle"** with a three-item `Use when:` list. Pat
  names no such principle. The neighbouring quote is genuine and was kept — its
  *form* was fixed (a partial quote stitched mid-sentence, now quoted in full).
- **Mechanical verification:** every block-quoted sentence in `context/` was
  tested against the full four-book corpus — **1,936 checked, 1,840 matched
  verbatim.** All 96 residual were adjudicated individually by four fresh
  agents prompted to *refute*, as artifact, correctly-sourced non-book
  material, wrong-citation, or fabrication. Roughly half were checker
  artifacts:
<!-- spellchecker:off -->
  hyphenation at a line break (`struc- tural`), a space eaten at a
  break (`second-personnarrative`), a **drop cap**, U+2003 em-space
  separators, `[[FIG:]]` splitting a sentence, and the 2014 hard-wrap.
<!-- spellchecker:on -->
  **The checker's own limits are recorded with it**, because they bound this
  claim: it reads only `>` block-quotes, so tables, inline quotes and fenced
  blocks are not covered — and two of the defects found in the verification
  pass were bullet lists that could never have appeared on a quote list.

### Fixed — fabrication-by-correction, a defect class in the opposite direction

- **The plugin had silently corrected Pat's typos.** 1991 Chapter 7 prints "your
  verbs will all already **by** POV neutral"; the file had it as "be". Confirmed
  a book typo in the raw XHTML, and restored with a do-not-correct note.
<!-- spellchecker:off -->
- Now marked as printed and protected from future "fixes": `swiftless`,
  `frictatives`, `Famly`, `Percy Bysshe **Shelly**`, `Ozymandius`, and "YOUR
  CHORUS YOU WROTE".
<!-- spellchecker:on -->

### Fixed — citations

- **Two `Book N` citations were live on `main`**, hidden from the regression grep
  by line wrapping: `beyond-books.md` ("overlaps Book / 2 Chapter 18-21") and
  `object-writing.md` ("across Books / 2 and 3"). **The single-line grep in use
  has a false negative** — the wrap-safe form is
  `grep -rnPzo "Books?\s+[1-4]\b" | tr '\0' '\n'`.
- 2014 Chapter 9's boundary corrected from the running heads: spine **120-131**,
  with 132 being the **Afterword**.

### Added — verbatim restorations

- **1991 Chapter 5 and Chapter 7 in full**, closing the 1991 book: the five hook
  strategies as printed, the A/B/C forward-motion cases, TARGETING (named in the
  book, not "in lectures"), the strategic-position passage, Chapter 5's
  BUILDING SECTIONS material and its four juggling parameters.
- **1991 Exercises 34-38 and 39-44 restored verbatim**, recovering the song
  titles and hooks the paraphrases had genericized away — `SOUTHERN COMFORT`,
  `TEDDY DOESN'T LIVE HERE ANYMORE`, `YOU DON'T HAVE THE BEST OF ME YET`,
  `I SLIPPED AND FELL IN LOVE`, `LAST NIGHT'S LOVE` and others — plus Pat's
  printed answer slots.
- **2014 Chapter 1's secondary-stress pages**, absent entirely, restored.
- **2014 Chapter 4's central worked example** — Warren Zevon's "Hasten Down the
  Wind" with all four rhyme-type versions — was missing and is restored.
- **2011 Challenge 1's material**: the Chekhov epigraph, the *writus
  interruptus* passage, Group Writing, and the objectwriting.com contest
  provenance that explains the named sample writers.

### Fixed — verification pass (four fresh agents, prompted to refute)

- **`verse-development.md` claimed a nine-item "power positions" list.**
  *Writing Better Lyrics* (2009), Chapter 7 prints **no such list** — only a
  Moral naming **three** families. An eight-bullet "surprise positions" list had
  four items absent from the chapter, and **Exercise 12 had been inflated from
  one printed paragraph into six bullets**, two of which Pat never asks for.
  `EXERCISE` returns zero hits in that chapter, so the file's ten step-lists are
  now labelled as the file's own rather than Pat's.
- **`rhyme-fundamentals.md` carried an invented compressed quote** — `"Rhyme is
  like the accelerator pedal." — Pat`. Pat's printed text (1991 Chapter 4, "II.
  PACE") is "Rhyme is like the accelerator in a car: the closer the accelerator
  gets to the floor, the faster the car moves…". Restored in full.
- **`lyric-melodic-roadmaps.md` hijacked one of Pat's terms** — it claimed "Pat
  names this state explicitly" while redefining his 1991 term *through-written*,
  which has 10 corpus hits all meaning something else. Also removed a fabricated
  "Pat cites Lady Antebellum…" attribution and an invented "misses 80% of
  mismatches".
- **`metaphor.md` had an invented four-row Imagination/Fancy table** placed
  directly beneath a real Coleridge quotation and contradicting the paragraph
  below it; Pat's whole statement is one sentence about degree.
- **`cliche.md`'s Exercise 10 was inflated from two steps to five**, and an
  invented four-bullet "Use this test:" replaced Pat's actual two-part rule.
- **`meter.md` carried a wrong scansion inside a fenced block** — figure
  `image_rsrc30K` prints `Knowing no one else can see` as `/ u / u / u /`; the
  file had `no`/`one` swapped. Caught only by rendering the figure at 12×.
- **An editorial gloss sat *inside* a block quote in `song-forms-examples.md`**,
  wearing Pat's voice. Moved out.

### Changed

- Two probes from the audit ledger are resolved with verbatim evidence: the
  "Can't Fight This Feeling" five-stress claim is **supported** (1991 Chapter 5
  prose plus Chapter 7's scansion figures — though **Chapter 7 never uses the
  word "duple"**), and the "Years" composite-balance claim is **supported in its
  arithmetic** while a trailing paragraph asserting bar counts was **invented**
  and removed.

## [0.8.6]

**Wave A cleanup — the five research files the previous pass left unfinished,
plus an extractor bug that had been silently corrupting every quoted stanza.**

### Fixed — the extraction bug, which reaches back into 0.8.5

- **`<br>` carries attributes in these EPUBs and the extractor was missing
  them.** The sources are Calibre-produced and write line breaks as
  `<br class="calibre2"/>`, which a `<br\s*/?>` pattern does not match; the
  tag-stripper then removed them, so **every lyric stanza arrived as a single
  run-together line**. Agents restoring those stanzas were **inferring the line
  breaks**. Corrected to `<br\b[^>]*>` and the corpus re-extracted.
- **This is a correctness bug, not a cosmetic one** — line count is what
  balance, stability and scansion claims are *about*. Re-verifying against the
  corrected source immediately caught a real error: the stagnant sheriff Box 3
  in *Writing Better Lyrics* (2009) Chapter 6 is **two printed lines, not one**.
- **The spine/image invariants do not detect it** — all four passed cleanly
  before and after. A stanza spot-check has been added to the extractor gate.
- **The ~9,000 lines restored in 0.8.5 were built with the buggy pattern** and
  have not been re-verified. Recorded for the verification pass.

### Fixed — fabricated material removed

- **`rhyme-types.md` carried an invented Pat quote.** A pull-quote reading
  "Craft prepares you to be creative." appears **nowhere in any of the four
  books**. Replaced with the real sentence from *Essential Guide to Rhyming*
  (2014), Chapter 9.
- **`stable-unstable-meta.md`, a 201-line file, held seven separate
  fabrications** — an unsourced "central emotion" `— Pat` quote (zero corpus
  hits), an epigraph falsely attributed to Berklee Online, an entirely invented
  "five motion controllers" table (`melodic rhythm` and `harmonic rhythm` return
  zero hits corpus-wide), invented stability-lever rows, a fake tone-of-voice
  quote, an invented "Pat's stance" paragraph with invented examples, and an
  invented table column plus a phantom pre-chorus row. All replaced with Pat's
  actual five elements of structure from *Writing Better Lyrics* (2009)
  Chapter 18, or relabelled unaudited where no book source exists.
- **`repetition.md`'s hidden-question and hidden-command matrices were
  invented**, including a fabricated "Effect" column. Replaced with Pat's
  printed `do` / `did` / `will` blocks and the real
  *You tell me / Tell me / Want me* sequence.
- **`box-model.md` was largely invented above the citation line.** Removed: the
  three-tier box-weight scheme, an entire fabricated **"Other named division
  axes"** table (Time of day / Season / Location / Sense / Speaker stance /
  Distance — no such list exists in either chapter), an invented three-bullet
  "travelogue test", an invented three-bullet "same-color test", invented
  You-I-We and Past-Present-Future bullet glosses, invented failure-mode rows,
  and editorializing Pat never wrote ("if Box 3 is lighter than Box 2, the song
  sags"). Each replaced with Pat's actual passage — the stack-of-boxes
  paragraph, his Hawaii travelogue definition, his colored-spotlights paragraph
  and his real worked diagnoses. **"Same-color" is this file's shorthand, not
  Pat's term, and is now labelled as such.**
- **`box-model.md`'s "One More Dollar" section was a prose plot summary.**
  Replaced with Pat's printed lyric and the real box diagram
  (Working / Gambling / Panhandling to get home), read off the figure.
- **`point-of-view.md` was scaffolded with invented apparatus.** Removed five
  separate invented "Use when" lists, an invented four-question direct-address
  "fact test", invented translation "tests", and a fabricated
  *One walks into the room / You walk into the room* example. Replaced with
  Pat's actual one→you substitution on the Seger couplet, his real one-sentence
  test, his printed narrative rewrites, and the songs he actually names —
  "The Great Pretender", "Sentimental Lady", "Dress Rehearsal Rag",
  "Digging for the Line" and "As Each Year Ends", none of which the file named.
  Pat prints exactly **four** direct-address listener positions; the file's
  count is now his.
- **`stable-unstable-meta.md` debunked "central emotion" at the top and then
  kept using it as a diagnostic key.** The fabricated quote was replaced, but
  the worked diagnostic, the coaching prompts and the anti-patterns still keyed
  off the invented phrase. All three now use Pat's actual wording from
  *Writing Better Lyrics* (2009) Chapter 18 — **"central intent, idea, and
  emotion"**. A provenance section was added naming the two things in the file
  that are **not** Pat's: the tone-of-voice axis (non-book, 0 corpus hits) and
  the worked diagnostic (this file's own applied example).
- **Two restored quotes lost their italics and so looked like transcription
  errors.** "you already knows all this stuff" and "a kind of universal feeling
  that you seems to add" both read as subject-verb slips. They are not: the raw
  XHTML italicises **`you`** in each, because Pat means the *word* `you` as a
  mentioned term, which takes a singular verb. **Both sentences are correct as
  printed**; the italics are now restored. This is a second, subtler failure
  mode of the extractor — stripped italics can make correct verbatim text look
  broken and invite a "correction" that would corrupt Pat's actual words.
- **`point-of-view.md`'s own header over-claimed.** It said the file names "the
  song and writers"; "Sentimental Lady", "Digging for the Line" and "As Each
  Year Ends" carry **no writer credit** in Pat's text or the permissions page,
  so it now says "the song, and the writers where Pat names them."
- **`repetition.md` had silently truncated a quote** (a dropped opening clause,
  then recapitalized) and **softened a categorical rule** — Pat writes that the
  device *only* works in first and second person. Both restored.

### Changed — the License section now describes what is actually here

- **`README.md`'s License paragraph was factually false.** It claimed the plugin
  "contains distilled craft guidance and short verified anchor quotes, not book
  text." It has not been true since 0.8.5. Rewritten: MIT covers the plugin's
  own code, skills and prompts and does not extend to quoted material; the
  research files reproduce Pat's text and the lyrics he analyses verbatim, as a
  deliberate decision by the owner, who owns all four books and is the only user;
  Pat's writing remains his and the lyrics remain their writers'; readers who are
  not the owner get no rights to any of it from the MIT header, and are pointed
  at the four books.
- **`point-of-view.md` had invented its own no-full-lyrics rule** — "Complete
  third-party song lyrics are not reproduced" — and cut lyrics to fragments,
  leaving it inconsistent with `box-model.md`, which reproduces them in full.
  The rule was never the owner's; it is revoked and the header now says so. The
  "As Each Year Ends" stanza is restored to Pat's full six lines. **Some
  excerpts in that file are still short; this is recorded there as a known gap
  rather than a policy.**

### Fixed — a second sweep, and the scaffolding thesis measured

- **`audit-checklist.md` was nearly half wrong, box by box.** 192 lines carrying
  26 chapter citations and **zero reproduced text** — pure `- [ ]` scaffolding
  attributed to specific chapters. All 83 checkboxes were tallied against the
  cited chapters: **42 traceable, 15 distorted, 26 invented.** Traceable boxes
  now quote Pat's actual sentence; distorted ones are corrected; invented ones
  are relabelled as this file's own synthesis rather than deleted, so the owner
  can see what is his tooling's invention and what is Pat's. **11 false section
  attributions** were fixed.
- **`bridge.md` opened on a six-word quote.** `"A bridge isn't a verse."` was
  bare and uncited. The sentence is real but was **truncated** — Pat's full
  passage in *Writing Better Lyrics* (2009) Chapter 23 goes on to contrast the
  bridge against verse and chorus. Restored in full and cited, along with
  Exercises 49 and 50 (entirely absent), the 1991 Chapter 5 five-point bridge
  definition, and the transitional-bridge list — each restored as Pat's printed
  numbered list rather than a flattened paraphrase.
- **A fabricated alias pair in `bridge.md`.** The file listed "channel" and
  "runway" as names for the pre-chorus. Zooming the actual figure shows Pat
  lists only Pre-Chorus, Climb or Lift, Vest, Verse Extension, Ramp and Prime.
  Removed. **This one was only catchable by reading the image.**
- **A fabricated quote in `response-filter.md`**, plus a quote misattributed to
  *Writing Better Lyrics* (2009) Chapter 1 that is really Chapter 5. Several
  Berklee-sourced blockquotes elsewhere were de-quoted rather than left
  masquerading as Pat's printed words.
- **`cliche.md` presented two couplets as displayed stanzas.** Pat quotes both
  inline in running prose, slash-separated. Corrected to match.

### Verified — the line-break damage is narrower than feared

The `<br>` bug was reported as potentially affecting all ~9,000 restored lines.
**Measured, it does not.** Every quoted block in all 49 research files was
checked mechanically — **1,109 consecutive line-pairs** — for the specific
corruption signature, a file splitting a line the corrected source keeps whole.

27 candidates surfaced and nearly all were legitimate: 14 in `phrasing.md` are
Pat's own deliberate split into **eight short phrases**, and the rest are
dialogue split per speaker, contrasted variant lines, and a wrapped thesaurus
entry. **Only `cliche.md` needed correcting.** A proposed "fix" to `hook.md` was
checked against the raw XHTML and **rejected** — there is a `<br>` between every
line there, so those are genuinely separate printed lines and joining them would
have introduced the very corruption being hunted.

**The shape of the defect, now that five files have been done at once:** the
paraphrase rule did not merely omit Pat's text, it **replaced it with invented
scaffolding** — "Use when" lists, bullet "tests", checklists, named axes and
failure-mode tables that read like craft guidance and cite nothing. This
apparatus is the single most common fabrication form found, it is present in
every file examined, and it is more dangerous than a wrong quote because it
looks like the useful part.

### Fixed — citations and claims narrowed

- **`box-model.md` was cited to *Writing Better Lyrics* (2009) Chapters 6-9,
  22-23.** Chapters 22 and 23 contain **zero** occurrences of "box". Narrowed to
  Chapters 6-9.
- **`five-compositional-elements.md` claimed the 1991 book has "no family,
  additive, assonance, or consonance vocabulary".** Narrowed rather than
  deleted: family, additive and assonance are genuinely absent, but
  *Essential Guide to Lyric Form and Structure* (1991) Chapter 4 names
  **Consonance Rhyme** in the Shelley analysis.
- **`rhyme-types.md`'s "six rhyme types" count was checked and left unchanged** —
  the reported count/list disagreement was not real.
- **Exercise 8.7 is genuinely absent from the printed book.** *Essential Guide
  to Rhyming* (2014) Chapter 8 runs 8.1-8.6 and 8.8-8.10, confirmed against the
  page scans rather than the text layer alone, because a numbering gap is
  normally an omission detector. `rhyme-sonic-bonding.md` already said so.

### Restored — Pat's verbatim text

- **`box-model.md`** — the form-neutral box definition, the progressive-weight
  passage, the division-of-labor principle and the "Between Fathers and Sons"
  analysis, from *Writing Better Lyrics* (2009) Chapters 6-9.
- **`point-of-view.md`** — the perspectives, the Hangman material and the
  Chapter 13 dialogue, from *Writing Better Lyrics* (2009) Chapters 10-13. Its
  Berklee Online material was deliberately left untouched and marked unaudited;
  **no quote was invented for a source that cannot be read.**
- **`stable-unstable-meta.md`** — Pat's actual stability wording, the film-score
  passage, the high-wire opening and the "Can't Be Really Gone" reading.
- **`repetition.md`** — the sheriff summaries and box sets, the
  "I'd just like to know" three-box demo, the neutral chorus, and the
  "Strawberry Wine" and "Unanswered Prayers" analyses with their songwriter
  credits.
- **`song-forms-examples.md`** — Pat's worked form analyses from *Essential
  Guide to Lyric Form and Structure* (1991) Chapter 6: the missing verses of
  "This Bottle and Me", his three-purposes bridge passage, the Ballad Stanza
  introduction with the "Western Wind" and "The Unquiet Grave" quotes, and
  Exercises 35 and 38. The file's header also claimed these were "canonical
  songs"; they are **Pat's own demo lyrics**, and now say so.
- **Figure-only content recovered.** Several passages in 1991 Chapter 6 exist
  **only as images**, following a dangling colon in the text — including the
  AABA **statement / restatement / variation / return** table, the S1/S2/S3
  bridge diagrams, the ABAB ballad-stanza principle and the verse scansion
  strips. The chorus walk-through phrase attributions were also corrected
  against the figures, so each of Pat's sentences now sits beside the printed
  phrase it describes.

## [0.8.5]

**A reversal of standing policy, plus a source-fidelity pass.**

Every previous release of this plugin was built under a "paraphrase only —
never reproduce Pat's text" rule that had been propagating through eight
handoffs. **That rule is revoked.** The repo owner owns all four books and this
reference is for their own use, and the paraphrasing was actively destroying
the value of the craft guidance: an exercise summarized is not an exercise, and
a worked example described is not an example. Pat's actual text, actual
examples, actual exercise wording and actual printed answer keys are being
restored across the whole knowledge base.

This release covers *Essential Guide to Lyric Form and Structure* (1991)
Chapter 4 (Rhyme), read in full with **all 40 of its figures** at 3x upscale,
plus the first wave of the verbatim restoration across the other research
files. Two findings below came only from the figures: the balance-paradigm set
and the printed exercise answer keys, neither of which exists in the text
layer.

### Restored — Chapter 4

- **Pat's two worked `aabb` / `abab` sections are back in `rhyme-strategy.md`
  in full**, as he wrote them, with the Exercise 27 instruction to reverse
  them. Likewise his worked `ABACCB` plot sketch and rhyme words from Exercise
  28, his "Ready or Not" verse and chorus, and both `abcccb` acceleration
  examples including the feminine-rhyme comedy version.
- **The closure sections now show Pat's actual word-schemes** rather than bare
  letters: both deceptive continuations, both non-deceptive open contrasts,
  both unexpected-closure cases, and the paired `aaa` illustration that
  distinguishes looking-backward identity from a genuinely open odd-count
  system.
- **The three labeling drills now carry their printed answer keys** (Ex 23, 24,
  25), transcribed from the page scans. Ex 24 #6 independently confirms `abba`
  is open. The keys are printed rotated 180° at the foot of each scan; reading
  them in place gets them wrong, so they were re-read from cropped, rotated,
  4x-upscaled strips. Ex 23 #7 is `T` — consecutive rhymes do not fragment when
  they follow an odd phrase count, which the chapter states outright.
- **Three fabrications, not just omissions.** `rhyme-types.md`'s weak-syllable
  examples (`mountain/certain`, `shadow/window`, `ringing/falling`) were
  invented — the chapter names weak-syllable rhyme but never defines it.
  `form.md`'s transitional-bridge list carried ten names where the chapter
  prints six, adding "channel" and "runway", splitting "Climb or Lift", and
  attaching genre and era attributions the book does not make; its heading also
  cited *Writing Better Lyrics* (2009) Chapter 13, which is "Dialogue and Point
  of View". `exercises.md` invented its item counts. The paraphrase rule did not
  only omit — it produced authoritative-looking inventions.
- **`bridge.md` attached the "four times is a lot" warning to `V/Ch/V/Ch`.**
  *Writing Better Lyrics* (2009) Chapter 22 attaches it to `v/v/ch/v/v/ch` —
  four verses, four trips. `song-forms.md` was right all along. Long-standing
  known defect, now closed with the verbatim passage.
- **`exercises.md` was missing Ex 32 and 33**, jumping 31 → 34. Both are in
  Chapter 5. Restored; the 1991 numbering now runs 1-44 unbroken.
- **The Marvell and Shelley passages are quoted** rather than described — both
  public domain — with the consonance-rhyme gloss Pat attaches to
  "Ozymandias."

### Restored — across the knowledge base

Twenty-nine research files were swept. Pat's real examples, exercise wording,
worksheet layouts and printed answer keys replace the summaries that stood in
for them. Highlights:

- **`exercises.md` no longer advertises that its exercises are paraphrases** —
  they were, which meant not one numbered exercise in the file was actually
  Pat's. They are now.
- **`rhyme-types.md`** — every stability tier now carries Pat's own definition
  wording and his actual example word-pairs, tier by tier. This is the file the
  rhyme skill runs on.
- **`daily-practice.md`** — the 56-day curriculum now lists Pat's real seeds
  and day titles with his numbering, replacing "(paraphrased shape)" stubs.
- **`prosody.md`, `meter.md`** — Pat's actual scansion strips, motion/emotion
  demonstrations, and worked stress examples.
- **`five-compositional-elements.md`** — Pat's full "Some People's Lives"
  demonstration, including the counterfactual rewrites and his commentary on
  why the one-row change matters at song scale.
- **`worksheets.md`, `rhyme-worksheets.md`** — real worksheet layouts and
  Pat's numbered step text, quoted.
- **`song-forms.md`, `song-forms-examples.md`, `form.md`, `hook.md`,
  `bridge.md`, `phrasing.md`** — worked song analyses with their real sections
  rather than "mechanism analyses (NOT lyric reproduction)".
- **`metaphor.md`, `cliche.md`, `object-writing.md`, `repetition.md`,
  `verse-development.md`, `box-model.md`, `title-game.md`, `idea-to-title.md`,
  `mosaic-rhyme.md`, `rhyme-sonic-bonding.md`,
  `rhyme-spotlight-connection.md`, `rhyme-dictionary-practice.md`** — real
  collision lists, cliche examples, sample writes, and rhyme demonstrations.

Web-sourced passages (Berklee Online, patpattison.com, American Songwriter,
Coursera) stay paraphrased and stay marked unaudited — those sources are not in
the corpus and nothing was invented to fill them.

### Changed — tooling

- **Scansion strips are wrapped in the spell-checker's block directive.** Pat's
  stressed-syllable vocalization is flagged as a misspelling of "DUMB", and it
  now appears verbatim in `meter.md`, `prosody.md` and `daily-practice.md`. An
  earlier revision of this branch added the exception to `_typos.toml`
  directly; that file is synchronized from `melodic-software/standards` and a
  local edit to it is silently dropped on the next sync, so the exception is
  applied with the inline `spellchecker:off` / `spellchecker:on` convention
  that config itself blesses. A permanent fix belongs upstream.

### Fixed

- **`rhyme-fundamentals.md`'s identity test asserted the opposite of the
  rule it was stating.** It said identity "matches conditions 1 and 2 and
  **also** matches 3" where condition 3 is *"different consonant sound before
  the vowel."* Identity fails condition 3 — that failure is the entire
  distinction. As written, the test passed every identity as a rhyme. Every
  other file in the plugin states the check correctly; this was the sole
  outlier.
- **`abba` was listed as a balanced pattern.** The chapter uses `abba` as its
  explicit counterexample — an opening `abb` is *not* balanced by returning to
  `a`; it is balanced by `abbabb` or `abbacc` — and the chapter's printed
  exercise key marks `abba` **open**. Since a balanced system is closed by
  definition, both sources agree it is neither.
- **`rhyme-strategy.md` contradicted itself about `abba`,** calling it
  "encloses" in the strategy table while its own Challenge 4 table listed it
  under floating instability. Resolved toward the source; the strategy table
  now states it stays open.
- **The balance-paradigm list was missing half the set.** Pat prints six
  (`abab`, `xaxa`, `aa`, `aabb`, `abcabc`, `xxaxxa`); the file carried three
  of them plus the counterexample.
- **`five-compositional-elements.md` described `abba` as a "wrap"** in a list
  where every neighbouring entry names a closure state, inviting the same
  wrong reading. Clarified that the frame returns without closing. The
  In Memoriam `abba` in `meter.md` is a **different frame** — Tennyson's
  equal-tetrameter stanza from the Challenge 4 curriculum — and was left
  untouched.
- **`rhyme-fundamentals.md` mislabeled a feminine-rhyme example as an
  identity** (`lonely / only`). It is a rhyme: the stressed syllables differ
  before the vowel. Its tail is identical, which the chapter explicitly
  permits without changing the classification.
- **Both files' image inventories omitted this chapter.** `rhyme-strategy.md`
  listed only its 2014 and 2011 sources; `rhyme-fundamentals.md` carried no
  inventory line at all. This is the **fourth** consecutive Book 1 chapter
  whose inventory concealed a defect.
- **Bare "Chapter 4" / "Chapter 9" references in `rhyme-strategy.md`** were
  genuinely ambiguous in a file citing three books — 2014 also has a Chapter 4,
  which `rhyme-types.md` uses. Qualified with title and year per
  `book-references.md`.
- **Seven remaining bare "Book N" citations retired**, in `audit-checklist.md`
  (2), `bridge.md`, `rhyme-generation.md` (2), and
  `templates/audit-checklist-prompt.md` (2) — constructions like "Books 1
  Chapter 4, 2 Chapter 4, 4 Chapters 4-6" that `book-references.md` prints as
  the counterexample. The plugin now has no bare "Book N" reference outside
  that file. Regression test:
  `grep -rn "Books\? [1-4]\b" context/ skills/ agents/ | grep -v book-references`
- **`exercises.md`'s header claimed its exercises were paraphrases** while
  carrying the restored verbatim ones — a stale notice that contradicted the
  file's own contents.
- **The Marvell / Shelley worked example appeared three times in
  `rhyme-fundamentals.md`** — a paraphrase in the flow section, the restored
  verbatim quotes, and a bullet restating Marvell a third time under a heading
  promising two examples. The verbatim quotation was prepended rather than
  substituted for what it replaced. Consolidated to one quotation with the
  other two positions now referencing it.

### Added

- **`rhyme-fundamentals.md` now names the chapter's five structural areas as a
  set** — balance, pace, flow, closure, type of closure — and identifies them
  as the Structural Pentad measured against rhyme instead of stress. The file
  previously covered all five without ever connecting them.
- **The through-written / fragmented pair is now linked to the rhythm
  Paradigms** it is drawn from: `abab` is the simplest through-written system
  "like rhythm Paradigm One," `aabb` the simplest fragmented one "like rhythm
  Paradigm Two."
- **Consonance rhyme is recorded as already named in 1991**, so the 2014
  stability scale extends that vocabulary rather than introducing it.
- The cheerleader analogy is now attributed to **both** 1991 Chapter 4 and
  2014 Chapter 1 — it appears in both, verified by extraction. The prior
  single-source attribution was incomplete, not wrong.

### Verified — no change needed

- **`prosody.md`'s "1991 Chapter 3-4 (Structural Pentad)" citation holds.**
  Its standing "Chapter 4 still unaudited" flag is cleared: Chapter 4 opens by
  naming all five Pentad properties and gives each a numbered section. Only
  the non-book sources remain unaudited.
- **`exercises.md`'s Chapter 4 block is complete** — Ex 18 through 28, no
  numbering gap.
- **`book-references.md`'s perfect-rhyme citation is accurate.**
- **`rhyme-types.md`'s page-scan inventory is genuine** — every cited
  *Essential Guide to Rhyming* (2014) filename resolves against a fresh
  extraction. Book 4's gate passes at 139 spine items / 139 images.

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
- **The skill handler still called "too cold" the reverse of greed.** After the
  frame split above, `skills/meter-prosody/SKILL.md` introduced too-cold as "the
  reverse case," reasserting the single-axis reading this release exists to
  remove — in the one file that drives behavior rather than documents it. Too
  cold is **orthogonal**, not a mirror image: the stresses land correctly and no
  stress check of any kind finds it. Now stated as an explicit negative, since
  merely softening the connective leaves the scan-for-it instinct in place.
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
