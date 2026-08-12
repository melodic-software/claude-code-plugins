# Changelog

All notable changes to the `songwriting` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [1.4.2]

### Fixed

- **The fleet model-tier directive was attributed to the writer with the wrong tier.**
  `object-writing`'s rule 6 said *"creative fan-out fleets run on Sonnet — the writer wrote it as
  `opts.model: 'sonnet'`"*. The source it names, the consuming workspace's
  `research/plugin-gaps.md`, says `'opus'`: *"creative fan-out fleets run on Opus (`opts.model:
  'opus'` per agent call), reserving the expensive model for the judge stage at most."* No session
  record has the writer authorizing a Sonnet fleet, and Sonnet has never been run against his bar.
  The rule now carries his wording, the evidence behind it — the Fable fleet's ~383k rejected
  tokens versus the Opus re-run that produced his only accepted candidates — and an explicit note
  that trading the tier down for cost is his call to make, not the plugin's.

  **This is the release's own failure mode, one release later.** 1.4.0 shipped a rubric whose
  pass 11 is voiceprint match and whose premise is that a named check and a run check are
  indistinguishable in the output; 1.4.1 then quoted the writer from memory and shipped it as a
  directive. Both files that carried the claim — the skill rule and the 1.4.1 entry below — cited
  a workspace log neither had reread.

## [1.4.1]

### Fixed

- **Object-writing fleet model tier** — fan-out dispatches use Sonnet, reserving Opus for judge
  or verifier stages.
- **Line-edit rubric pass 1** — road-sign on a strong slot is not a failure when the sung
  original already places that road-sign there (reconciles with `meter.md` step 8).

## [1.4.0]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226.** No Pattison reading, and **no new Pat text enters the corpus.**
Every Pat passage this release quotes was copied from a file already here and then
re-checked against the pre-change corpus by script rather than by eye:
**37 added blockquote fragments — 29 in `line-edit-rubric.md`, 5 in `meter.md`,
3 in `voiceprint.md` — and all 37 are verbatim in the corpus as it stood at the
fork point. Zero unfound.**

The wider sweep over every added `"…"` span finds 74 fragments, 53 of them already
verbatim here. The 21 that are not are this release's own new section titles
("Presenting the candidates — chat vs file"), router trigger phrases, one writer
utterance, and this entry quoting itself — no attribution among them. Blockquotes
are the fidelity axis, and they are clean.

**A minor, not a patch.** Two new context files ship, the line-emitting skills
gain preconditions they did not have, and one gate class becomes non-skippable.
That is behavior.

### ⚠ THE LINES WERE BAD, AND THE FILTER SAID THEY WERE FINE

1.0.0 recorded the finding this release acts on: *"the quality is contingent on
the response filter actually running"*, and **`response-filter.md` is therefore
the highest-leverage file in the plugin** — followed by the sentence that made
this release necessary: *"the filter is self-administered with no enforcement."*

It was used in anger, on a real song, and the prediction held exactly. Across the
Sofía sessions (2026-08-12) the plugin emitted line candidates that miscounted
stresses against a sung demo melody, repeated a content word across adjacent
lines in violation of its own discipline, offered a plain description labeled as a
metaphor, and presented lines it had *itself* flagged as off-template. The writer
caught every one. **The assistant had run the response filter as self-attestation
and passed itself**, then reported the boxes as clear.

The writer stopped songwriting until it was fixed. The findings are logged
per-gap, with the rejected candidates, in the consuming workspace's
`research/plugin-gaps.md`; the ten craft gaps triaged fix-now are what this
release closes.

**A plausible-looking pass is the failure mode, not an absent one.** Naming a box
and checking a box are indistinguishable in the output when the same context does
both — which is why almost every change below is about producing an ARTIFACT
rather than a verdict.

### Added — the per-emission cycle, and the register it is measured against

- **`context/pat-pattison/research/line-edit-rubric.md`** — eleven passes cycled
  on every candidate line BEFORE the writer sees it: positional fit,
  word-repetition at three radii, sonic bonding, rhyme audit, five-element delta,
  the §2 content boxes, dependency re-verification, register, metaphor validity,
  spotlight content, voiceprint match. Battle-tested in the sessions that
  produced it; each box exists because the writer caught a miss.

  **Its form is this repo's, and it says so per pass.** Every pass opens with a
  `Provenance:` line — Pat-anchored with a citation, or writer-derived. Passes 2,
  7 and 11 carry **no** Pat quote and state that plainly; `repetition.md` was
  checked and does **not** draw pass 2's named-motif-versus-unnamed-defect
  distinction, so pass 2 cites it as related reading only. This is the
  `audit-checklist.md` header pattern (*"The checklist form is this repo's, not
  Pat's… What is his is the material each box invokes"*), applied box by box.

  **It is a separate file for a reason the filter itself states.**
  `response-filter.md`'s own recheck table says *"Filter takes more than ~10s to
  apply on a typical output | Trim — fast filters get run, slow ones get
  skipped."* An eleven-pass cycle inlined into that gate would turn the gate into
  the thing that gets skipped. So §2 stays the OWNER of its content boxes and the
  rubric's pass 6 loads them — **one way, not two**, stated in both files.

  **And it is bounded against the file that already owns per-line checking.**
  `audit-checklist.md`'s per-line pass is **pre-LOCK** (the writer is considering
  committing an existing line); the rubric is **pre-EMISSION** (nothing has been
  shown yet). Both files now carry the distinction, in the same words, pointing at
  each other. A one-way pointer would have left the older file reading as the sole
  owner.

- **`context/pat-pattison/research/voiceprint.md`** — the writer's own register,
  built from their accepted lines: vocabulary band, syntax shapes, image density,
  irony level, each recorded with quoted evidence rather than an adjective.

  **This closes a gap where the plugin asserted a principle and shipped no
  mechanism.** `response-filter.md` §4 has always carried *"Coach toward writer's
  voice — the AI does NOT impose its preference"*, and its posture table opens on
  `Voice | The writer's voice | The AI's preferred voice`. Neither says what the
  writer's voice IS, and with no answer to that, "don't impose mine" degrades into
  a guess. The guess defaults to a fancy-plain dial, and the transcript shows the
  oscillation: `silt` rejected as too literary, then `cruel` and `too` rejected as
  too basic, while `picturesque` was accepted and `so` was never acceptable. Those
  are not four points on one dial; they are four observations about one band whose
  edges are set by whether a long word pays and whether a short word carries.

  **No Pat lineage is claimed, because there is none.** The file states outright
  that he publishes no such build. One quote licenses the TARGET — *"I decided to
  set four 14-day challenges to help you explore your writer's voice more fully"*
  (*Songwriting Without Boundaries* (2011), cited book-and-year because that
  sentence carries no Challenge or Day locator anywhere in this corpus) — and the
  file says in the same breath that it licenses nothing about the method.

  **The Sofía words are shipped as the FAILURE, not as the target.** A table
  records them as one writer's judgements on one night, with the wrong lesson the
  assistant drew from each. Shipping them as the plugin's register would have
  replaced the AI's preferred voice with one writer's — the same defect at one
  remove. What generalizes is the build. The artifact lands at
  `songwriting/shared/voiceprint.md`, cross-song, because register is a property
  of the writer; a deliberate per-song departure is a recorded craft decision and
  goes to that song's `decisions/`, where this corpus already records them.

- **A fixed-melody fitting procedure**, in `meter.md`. The corpus taught
  stress-count discipline for matching verse two to verse one; nothing covered
  fitting a replacement line to a melody that has already been SUNG.

  **Stress-COUNT matching was tested in production and it failed.** A five-stress
  replacement stressing syllables 2/4/6/11/13 was written against a sung line
  stressing 3/6/8/11/13 and died on the first sing-through. The procedure now
  matches syllable count **and stress positions**: transcribe from the recording
  rather than the lyric sheet, scan by importance, number the syllables and
  bracket the stressed ones, then compose into that template.

  Two findings inside it are worth more than the procedure. **The singer's
  phrasing outranks the inferred grid** — the grid read syllable 9 as weak and the
  writer pushed it on every take, so any road sign parked there got promoted and
  stuck out; forced-alignment tooling failed on the talk-sung verse, leaving the
  writer's own singing as the measurement. And **the sung original is the floor,
  not the ideal**: the demo itself sings a preposition on that slot, so a candidate
  reproducing that shape is no worse than what is sung today. Without that second
  rule the procedure stalls on impossible perfection.

  The `±1 syllable = one merged or split note` tolerance is labelled as the
  writer's own, and priced rather than absorbed — in production the 14-syllable
  variant of a 13-syllable slot was surfaced as a choice, not spent quietly.

### Fixed — the routing failure that caused the fitting gap

- **Scenario 2 and Scenario 4 never composed, and the auto-detect list is why.**
  `workflows.md` routed each signal to exactly one scenario, so a
  revise-this-demo request reached Scenario 2 (existing song revision) alone and
  Scenario 4 (writing to an existing melody) never loaded. Scenario 2 now carries
  a melody-locked precondition routing to **both**, with the fitting pass running
  *before* step 1 of its chain; Scenario 4 carries the already-sung sub-case; and
  the detect list gains the one signal that resolves to a **pair**.

  Fixing only the craft file would have left the router sending the next session
  down the same path.

### Fixed — force-loading, because a routing hint is not a precondition

- **`§2`'s `Reference:` line is a load list, not a bibliography**, and now says
  so. The three line-emitting skills state that §2 has not been run until
  `meter.md` and `phrasing.md` have been READ this session — plus `metaphor.md`
  when a figure is asked for. The gap was subtle and is the whole lesson: those
  files were already *referenced* through the filter checklist, so a skill could
  name §2 as run having never opened one of them.
- **`co-write`'s hard-gate table gained a `Craft sources read` row whose artifact
  is a citation of what the file settled for THIS line** — the stress count it has
  to hit, the phrase shape it has to keep. A filename is not an artifact.
- **That table's preamble was scoped to "a rhymed position"**, which would have
  let every source row be skipped for an unrhymed line. Every row now applies
  before any line is emitted; only the rhyme row is position-specific.
- Five Action Router `Load` cells that emit lines routed no craft source for
  stress or phrasing at all — `co-write`'s `line-brainstorm` and
  `section-brainstorm`, `diagnose`'s `variations` and `rewrite`, `workflow`'s
  `fragment`. The routing hint and the gate now agree.

### Fixed — self-attestation, replaced with a refutation

- **A skeptic pass is now a gate row**, and what it must show is *the strongest
  case AGAINST each candidate* — not a verdict. A line survives when its
  refutation is stated and judged insufficient; a return holding nothing against
  anything has shown nothing. The skeptic is dispatched blind, reading the sources
  at their paths, on the same hard-boundary mechanic that makes the
  `object-writer` fleet diverge. Its kill rules rank **singability and verbosity
  above cleverness** — the writer's own ordering.
- **This is instruction-level and needs no new component**, and the text says so
  ("no agent in this plugin is a skeptic") so a reader does not hunt for one. The
  preloaded-skill agent set is deliberately not shipped — see *Still open*.
- **Read-at-path, not context-provided, is load-bearing.** The 12-agent panel that
  produced the rejected batch was given inlined context and never read the corpus.
  That is why the row demands the sources be read at their paths.
- **The skeptic row is skippable-with-named-reason, and that is a judgement call
  this release made rather than one the writer handed down.** His standing rules
  cover the rubric self-run with no fatigue exceptions; they say nothing about
  mandating a subagent dispatch per batch. Making it unskippable would have been
  this plugin's decision wearing his authority, so it sits in the skippable class
  with the reason required and the note that being asked why is expected. **A
  reviewer who wants it mandatory should say so** — it is one word in one cell.

### Fixed — one gate class was two, and the skip clause covered only one

- **`Any gate may be skipped` was true of craft artifacts and false of the AI's
  own self-check**, and the file said only the first thing. The rows now split:
  everything demanding a craft artifact stays skippable-with-reason, because how
  much scaffolding a line gets is the writer's call and *"There are no rules, only
  tools."* (*Writing Better Lyrics* (2009), Chapter 18) is why. **The rubric row
  alone** does not carry that clause — the writer cannot overrule a check he never
  saw run. Under load, emit fewer candidates, not unchecked ones.

  Getting this wrong in either direction was the risk: a blanket
  no-exceptions rule would have contradicted the plugin's whole stance, and
  leaving the skip clause blanket would have made the new rules decorative.
  `response-filter.md`'s own §1-§8 box-level skips are explicitly untouched.
- **And "no exceptions" needed one distinction to be self-consistent.** Four of
  the rubric's passes are scoped by their own headings — fixed-melody work, a rhyme
  position, a figurative line, an existing voiceprint. Read against a flat
  no-skip rule, "pass 4: not a rhyme position" would be a violation, and pass 11
  openly said its own skip was legitimate. The rule now separates **not applicable
  by the pass's own scope** (declare which condition failed and step past — that IS
  the pass running) from **dropped because the cycle is long** (forbidden). Pass 11
  reports `UNKNOWN — no voiceprint on disk`, reusing the vocabulary
  `voiceprint.md` already uses for a dimension below its evidence floor. A
  self-contradicting rule is an unenforceable one.
- **A FAILED pass kills the candidate; it does not reach the menu with the flag
  attached.** A disclosed failure is still a failure shown, and the writer's
  attention is what the disclosure spends. Two new cross-section drift checks
  catch the regression — `Own-flag drift` and `Self-run drift` (a pass named as
  run with no marked artifact behind it).
- **Two rejected executions in a slot ends generation**, and the terms are defined
  so the rule can actually be applied: what a *slot* is, what counts as a
  *rejection* (declining the batch's execution, not asking for a tweak; rejecting
  the CONCEPT resets the count), and what the handoff contains instead of a third
  batch. **Two** is the writer's own threshold and is labelled as his.

### Fixed — the two vocabulary overcorrections, in opposite directions

- **The anti-cliche discipline was reaching past the words anyone sings.** The
  writer caught it on `silt`. `line-brainstorm.md`'s generation now runs in two
  passes with the order stated: **common stock first** — the plain words and the
  idiom stock someone would use telling this scene out loud — **then reframe**.
  The cliche scan moves to pass 2 and is explicitly *not* a pre-filter on pass 1.

  **This raises cliche exposure deliberately, and Pat supplies the exit** — put it
  *"in a context that brings out its original meaning or makes us see it in a new
  way"* (*Writing Better Lyrics* (2009), Chapter 5). Reframing is the answer to a
  flagged cliche; vocabulary escalation is not, and §2 now says so where its
  cliche scan previously ended on a bare "REWRITE".
- **The fix is NOT a prefer-plain-words dial, and pass 8 states that outright.**
  `picturesque` passes; `cruel` and `too` are as common as words get and were
  rejected as too basic. Pass 8 fails a word for being unsayable, never for being
  long or Latinate. **1.1.2 shipped an overclaim replaced by its opposite
  overclaim** and 1.1.3 had to repair it; that failure is the reason this one is
  guarded in the text rather than left to a reader's good sense.
- **The writer's "modern pop vocabulary is roughly the common few thousand words"
  ships as his premise with no figure attached.** It is not a measurement, and
  this plugin has deleted a `~70%` and a `~60%` for exactly that shape.
- **The say-it-aloud kill rule is reuse, not invention.** `cliche.md`'s rewrite
  pattern already said *"Read the old and new lines aloud"* under its own
  plugin-authored flag; pass 8 promotes it from a rewrite nicety to a gate.

### Fixed — rhyme search swept a column and called it the field

- **`§1`'s `Stressed vowel anchored` box was the instruction that failed.**
  Anchoring the vowel and then searching the source word's own coda returns one
  row and stops — `-ill` returns the `-ill` column and never reaches the rest of
  the field. `rhyme-generation.md` gains **Step 1b**: the source word's coda is
  ONE row; walk the other coda columns on the same stressed vowel.

  **Pat runs the field himself, in print, and this corpus already had the pages.**
  Chapter 7's keyword `risk` has a Perfect Rhymes column two lines long
  (`disc` / `(oops!)`) beside an Imperfect column crossing roughly fifteen codas on
  one short-`i`. The walk ORDER is labelled as this plugin's assembly of his two
  printed orders — Chapter 4's within-family sequence and Chapter 5's
  noticeability sequence — because **neither of them is a walk across codas**.
- **A third fail signature** joins §1's two. Both existing ones catch a list's
  surface; neither catches a tier-labeled, mosaic-complete, ≥8-candidate list
  whose every entry still sits on one coda. **The tell is what is ABSENT.** The
  writer's own quartet is the worked case: `chest / dress / picturesque / forget`
  spans four codas on one `ĕ` and all four pass the identity check.
- **A named word-family seed** — final-stress Latinate/French multisyllabics
  (`picturesque`, `silhouette`, `masquerade`) that column search never surfaces.
  Their phonetic property is what makes them usable: final primary stress, so they
  behave as masculine rhymes, on codas that are not the source word's.
  `charade`, `masquerade`, `parade` and `promenade` are **Pat's own printed
  candidates** in his `afraid` columns, so the pattern is licensed rather than
  invented. Marked as the writer's observation, not a measurement of pop usage,
  and explicitly not a licence to reach for rare words — the same writer rejected
  `silt`.
- **Datamuse was checked against the script rather than assumed.** No mode of
  `datamuse.sh` accepts a phonetic post-vowel constraint — `pattern` matches
  SPELLING — so the walk is recorded as internal-generation-only, with Datamuse
  confined to post-walk verification and breadth.

### Fixed — candidates the writer could not judge

- **Bare one-line candidates in a table forced the writer to re-embed each one in
  the section before he could sing it, and the singing is where the judgement
  happens.** `variations.md` now carries the writer's own convention: full section
  blocks IN CONTEXT, changed lines marked `►`, one labeled block per variation,
  3-4 per chat menu, deep analysis in the `variations/` file. A worked example
  shows the shape, since a shape is best specified by showing it.
- **`variations-prompt.md` literally labelled the metadata block "Format for
  output to writer"** — the exact shape that was rejected. That label was the
  contradiction and is corrected at its source; the block is now named as the
  recorded FILE shape, with the chat shape as its own step.
- **Two numbers looked like a conflict and were not.** §1 mandates ≥8 rhyme
  candidates and the posture table said `3-15 surfaced`, against the writer's 3-4
  cap. The row now separates **generated and recorded** from **shown per chat
  menu**, with a note stating that no generation volume drops. Generate wide,
  record everything, show few.
- **"Don't dump options inline" was being read as "show nothing singable."**
  `artifact-persistence.md` now defines the prohibited DUMP (the whole untrimmed
  set pasted into chat) against the required MENU. A variations response with
  nothing singable in it has not been delivered.

### Fixed — object-write register leaked into lyric slots

- **`Mine, never transcribe` was insufficient, not wrong.** The word bank was
  QUOTED rather than adapted: object-write prose has its own texture, and the
  agents pasted the texture instead of translating it. The section becomes
  **`Mine → adapt → say it aloud`**, and the middle step is marked
  plugin-authored — Pat draws the raw-material-versus-crafted-line distinction
  (*"with bushels of sense-bound images glittering on the kitchen table, what do
  you do with them?"*, *Writing Better Lyrics* (2009), Chapter 2) and prints **no
  translation procedure**. The SSOT's claim that the whole gate is "Pat's own" is
  two-thirds true and shipped that way.
- **Line length under free meter had no budget**, and a bridge ballooned to 13-
  and 14-syllable prose lines with nothing to catch it. `prosody.md` gains an
  envelope rule in the section that already owns line length: measure the
  stress-length range of the song's other sections and write inside it. Measured
  in **stresses**, per that section's own traffic-cop rule — a raw syllable count
  answers a different question. `"Free meter"` is recorded as workspace shorthand
  with zero corpus hits, not a Pat category.

### Fixed — the fleet inherited the session's model

- **`object-writer`'s frontmatter is `model: inherit`, so the DISPATCHER chooses
  the model and a dispatch that leaves it unset runs the whole fleet on the
  session's.** In the rejected batch that came to ~383k subagent tokens at
  top-tier pricing. Writer directive, recorded as his: creative fan-out fleets run
  on Opus, per agent call, reserving the expensive model for the judge stage at
  most. It lands in `object-writing/SKILL.md`'s numbered dispatch rules — the
  plugin's only place that recommends a fan-out — because the agent file cannot
  act on a rule about which model calls it.

### Placement — why two new files live under `context/pat-pattison/`

Neither file is Pat's method, and the author seam matters. They live there anyway,
on this repo's own precedent: `README.md` enumerates what
`context/pat-pattison/` holds as *"the full reference corpus, its templates, the
Datamuse script, and the mandatory response filter"* — naming a repo-authored file
as a resident — and `audit-checklist.md` has always declared its own form as this
repo's rather than Pat's. **The seam remedy is per-box provenance labelling, not
relocation.** A third sibling under `context/` was considered and rejected:
`context/<author>/` is the author seam, and a peer directory would break the one
story the README tells about extension.

### Still open

This release closes the ten craft gaps triaged fix-now and the four post-mortem
fix-nows. It closes **none** of the following, and none should be read as covered:

- **Rubrics-per-skill and book-grounded evals** (gap 6a). The skills ship `evals/`
  directories; populating them from Pat's printed worked examples — the "Some
  People's Lives" counterfactuals, the "50 Ways" consonance swap, the wind-as-dog
  drills — is real book work and is not done. The rubric this release promotes is
  the general case; the per-concern rubrics are not written.

  **The existing evals were read for conflicts and none was found**, but one is now
  under-specified: `skills/rhyme/evals/evals.json` expects the stability-tier walk
  and says nothing about the coda-field walk that must now precede it. Its `8-15
  candidates` assertion is a GENERATION count and is unaffected by the 3-4 display
  cap. No eval mentions the rubric or the voiceprint, because neither existed.
- **The narrative-information pass** (gap 8) — *what does the listener know at this
  point, and when should they learn the rest*. The corpus covers the craft in
  verse development and repainting; it has never surfaced as an operational check.
- **The preloaded-skill co-writer agent set** — `imagist`, `rhyme-strategist`,
  `prosodist`, `line-skeptic`. Validated in principle and deliberately deferred
  until the rubric and voiceprint had landed, which is now. The skeptic gate above
  is honoured by a general subagent in the meantime.
- **Constraint tightness as a quality lever.** The one salvageable slot in the
  rejected batch was the tightest template (a fixed 8-syllable chorus line), and
  the pattern is recorded but not folded into the co-write templates.
- **An audio-analysis capability** (gap 5) and a **`lyric-desk` generator** (gap
  6c). Both tracked in the consuming workspace; scripts and a v1 HTML page exist
  there.
- **The four Suno documentation items** (duration control, the Audio Influence
  default in the cover flow, tag-only chorus absorption, lineation as phrasing
  control). Independent of this change and deliberately not bundled with it —
  `skills/suno/**` is untouched here.
- **This release is not itself verified against a live session.** Every change is
  instruction-level, and the whole finding above is that instructions which merely
  *name* a discipline do not enforce it. The gates now demand artifacts, which is
  the mechanism intended to make the next self-report checkable — but whether the
  emitted lines clear the writer's bar is a question only the next real song
  answers.

## [1.3.0]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226.** No Pattison reading. Suno docs only; no craft skill is
touched.

**The source is live production use, not a reading pass.** A writer ran Suno
v5.5 through a real song on 2026-08-12 and hit four things the skill did not
document. One of them silently corrupts a generation: an empty `[Chorus]` tag
used as repeat shorthand, sitting above a `[Bridge]` that carried lyrics, and
Suno sang the **bridge's** lyrics in the chorus slot and dropped the bridge.
Nothing in the output announces that; you get a structurally wrong song that
sounds fine.

### A new evidence class, named rather than smuggled onto the ladder

Three of the four findings are **first-hand, single-session, n=1**. The
confidence ladder in `SKILL.md` grades *second-hand* sourcing — official docs,
multiple community guides plus Reddit consensus, or a single community post — and
none of those rungs describes a writer driving the product and watching what
happened. So `SKILL.md` gains one bullet placing these **off** the ladder, with
a fixed label carried at every claim site:

```
writer-observed, single session (2026-08-12), n=1 — not externally corroborated
```

**No new rung was invented**, per 1.1.3's precedent — the gap is named instead.
The bullet also fixes the direction the label could be misread in both ways.
First-hand does **not** outrank MEDIUM: one unreproduced session is not
consensus, and a flow-scoped reading must carry its scope. But an observed
**failure** is existence evidence in a way a claimed success is not — enough to
document a fix, never enough to assert the failure always happens or to state a
mechanism.

**That distinction is the whole discipline of the S3 entry below**, and it is the
trap 1.1.2 and 1.1.3 were both written about. One absorption proves tag-only
repeats *can* fail in that adjacency. It does not prove they always fail, and it
does not establish why. The entry says the adjacency is *the observed correlate,
a candidate cause, not a demonstrated mechanism*, and the fix it recommends is
the cheap safe default — write the lyrics out — not a prohibition. This skill's
own `tips.md` warns that variance is high and one generation is rarely
representative; that warning applies to the single run behind this finding too,
and the entry says so.

### Added

- **Duration control is documented, and first-party verification succeeded.**
  Suno's release notes, Jul 20 2026: *"Drag the new Duration slider in the Create
  form to pick your song length. Available on Web using V5.5 model"*
  (<https://suno.com/release-notes/duration-slider-on-web>, fetched 2026-08-12).
  So the control's existence, name, home, and Web + V5.5 scoping are **HIGH**,
  not writer-observed — the label above does not appear on them.
  **The four claim classes are rated separately rather than averaged.** Range
  (10s-6min), 5-second increments, and the Auto/Custom pair are **LOW-MEDIUM**:
  the writer read them off the UI and one community post states the same figures
  independently, which makes the range the one writer-observed item here that is
  *not* uncorroborated — but no `help.suno.com` article states a range, and two
  guides written *about* the slider decline to state one. "Target, not a
  guarantee" is carried as an attributed quote.
  **The lyric-length interaction ships as an explicit OPEN QUESTION** with a
  do-not-advise instruction on it. A single post reports hard-cut and rushed
  delivery, and the temptation was to believe it because this skill already
  documents the same failure family from the lyric-length end (past ~3,000 chars
  Suno "rushes, skips sections, or cuts output short"). **A shared failure shape
  is not evidence of a shared cause**, and the entry records the two-generation
  test that would settle it. A "golden length" sweet spot offered by the same
  post is deliberately not carried: one source, one taste judgement, one
  round-number range — the shape this plugin has deleted twice.
- **Two troubleshooting entries for failures that were tested, not theorized** —
  "My bridge is missing / another section sang its lyrics" (the absorption above)
  and "There's too much pause between lines / the delivery is choppy", plus a row
  each in the master pitfalls table.
- **Audio Influence has an entry value at last, scoped to the flow it was seen
  in.** 25% on entry to the **cover-from-upload** flow. Recorded as
  per-entry-flow deliberately: the Extend and upload-as-seed flows were **not**
  observed, and the text says so rather than promoting one reading to "the
  default". Cover-workflow guidance now states the trade the slider makes —
  uploaded-melody fidelity against new-arrangement freedom — with the cost named
  in **both** directions, and notes the consequence of the observed value: a
  cover-from-upload opens *low*, so its untouched behavior is arrangement
  freedom. If the melody is the asset, that is a setting to change deliberately
  rather than inherit.

### Fixed

- **Two blanket confidence sentences would have mislabeled the new number, and
  both are carved out.** `advanced.md`'s Creative Sliders section opens by
  declaring *every* percentage and default below community-empirical, and
  `SKILL.md`'s MEDIUM rung says the same of *every* numeric slider setting in the
  skill. The Audio Influence entry value is neither. Adding it under either
  blanket would have shipped a first-hand reading wearing a community-empirical
  label — so both sentences name the carve-out, in the same bolded clause that
  does the governing.
- **The five-controls count in `advanced.md`'s More Options panel survives,
  because the evidence moved the feature instead.** The gap report proposed
  documenting duration under More Options, which would have made that count
  wrong. First-party evidence puts the slider in the **Create form**, so the
  count stands at five and the panel gains a guard saying where the control
  actually is — positive evidence of its home, not an assertion from silence
  that the panel lacks it.
- **`v55-features.md`'s 2026-07-18 verification stamp is amended rather than
  left to imply completeness.** The slider shipped Jul 20 2026 — two days after
  that pass. It is deliberately kept **out** of the version-delta table, which
  tracks model capabilities rather than Create-form controls; a row there would
  misdate a July Web control as a March model capability.
- **"One idea per line" no longer contradicts the new join-the-lines fix.** The
  skill asserted it unqualified in **three** places — `lyrics.md`'s Performance
  shaping table, `lyrics.md`'s Best practices, and a `tips.md` entry the gap
  report did not name. It is the same mechanism read in two directions:
  separation is what a line break buys, so short-line stacks buy too much of it.
  `lyrics.md` now owns the full statement ("Line breaks cut both ways"); the
  other sites qualify and point at it rather than restating the claim.
  **No line-length floor is invented** — no source states a number, so the test
  is qualitative: a clause holds, a fragment over-instructs.
  The fix is explicitly **prompt-layer only** — the page lyric keeps its artistic
  lineation, and the text says outright that nothing here asks a writer to
  un-write a line.
- **"Reuse the chorus verbatim" now says to write it out.** That bullet was
  silent on whether the reuse had to be typed under each tag, which is precisely
  the reading that produced the absorption failure.

### Ledger

Six rows added to `reference/suno-drift-audit-ledger.md` (S13-S18), per its own
rule that a row and the CHANGELOG move in the same PR. Three record *audit
outcomes* (S13 first-party confirmed; S14 LOW-MEDIUM; S15 the open question);
three record the off-ladder observations (S16-S18). S15 exists so the duration /
lyric-length question is falsifiable rather than rediscovered — the reason this
ledger was created in the first place (#2354).

### Known gaps

- **Tag-only as the FINAL section before `[Outro]`/`[End]` is untested** and
  flagged as such at the entry and in S17. Neither endorsed nor ruled out.
- **No external corroboration pass was run against the three observed findings.**
  `SKILL.md` documents a working browser route to r/SunoAI; running it is the
  specific event that would move S16-S18, and it was not attempted here. Named
  rather than left as an implied absence, because "not corroborated" and "nobody
  looked" are different claims and 1.2.0 was written about confusing them.
- **`troubleshoot.md` still has no song-length symptom.** Now that duration is
  documented, "rushed delivery" acquires a second candidate cause, and the
  garbled-lyrics entry owns the adjacent one. Out of scope here; flagged so the
  two files do not drift.
- **Version class ruled minor (1.3.0).** New standing instructions (off-ladder
  writer-observation bullet), feature-route content (Duration section), and two
  troubleshooting behaviors match 1.2.0's precedent for minor bumps. Sibling
  `feat/songwriting-emission-discipline` can take the next minor after rebase.

## [1.2.0]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226.** No Pattison reading.

**A minor, not a patch.** A confidence rung changes, which changes how callers
are told to surface the technique, and `SKILL.md` gains a new standing
instruction (the browser route to Reddit). Both are behavior, not wording.

**The r/SunoAI pass that three releases called impossible was run.** 1.1.2 and
1.1.3 both recorded the Reddit corpus as unreachable — "the search tool refuses `reddit.com`" — and rated claims down
accordingly. A reviewer on PR #2366 pointed at this plugin's **own**
`context/workflow-recipes.md`, which has said since 1.1.0 that *"r/SunoAI is no
longer unreachable"* and that a **browser session** reaches it where search and
direct fetch fail. The route worked on the first try.

**The corpus was never closed. The note saying so was never read.** That is the
finding worth keeping: an absence recorded as "cannot be checked" is only as good
as the search for a way to check, and the way was already written down in this
skill.

### One claim moves up a rung; the other does not, and that is the more useful result

- **Tag-order front-loading (`power-tips.md` "Tag order") is no longer
  unsourced.** 1.1.1 demoted it as *"never been checked against a source in
  either direction"* and 1.1.2-1.1.3 left it there. An upvoted r/SunoAI guide
  post (13 votes, 28 comments,
  [`1h4zc7e`](https://www.reddit.com/r/SunoAI/comments/1h4zc7e/expanded_insight_and_guidance_on_suno_style/))
  leads with **"Key Insight 1: Order Matters"** and states that Suno assigns
  importance by order, first descriptors setting the stage and later ones adding
  flavor, with a paired example differing only in which half leads. Now
  **LOW-MEDIUM** — the ladder defines that rung as *"at most a single community
  post"*, and one post is what this is. Not MEDIUM.
- **Bare genre order is still unestablished, and now we know what would settle
  it.** In
  [`1g5qzes`](https://www.reddit.com/r/SunoAI/comments/1g5qzes/style_order/) a
  user reports `progressive metal, jazz` and `jazz, progressive metal` giving
  different results. A draft of this release called that **isolating**, because a
  comma swap moves order and nothing else. **A reviewer showed it is not** — and
  the refutation came from this plugin's own `tips.md`: *"Variance is high. First
  generation is rarely best."* Against a stochastic generator, one run per
  ordering leaves run-to-run variance uncontrolled; two different outputs are
  what you would expect from the **same** prompt twice. Recorded as an anecdote
  and as the shape a real test would take — repeated or seed-controlled — not as
  evidence.

**"Order encodes priority" is still not restored.** Its defect was certainty and
mechanism, and none of this supplies either.

### Fixed

- **Genre fusion stays between LOW-MEDIUM and MEDIUM — but now on evidence.**
  `SKILL.md` requires multiple guides **plus** Reddit consensus. Three guides
  give the first half; the pass found **one** corroborating post and one split
  thread, which is corroboration, not consensus. The rung is unchanged from
  1.1.3; what changed is that 1.1.3 rated it down for an **untried** corpus —
  wrong twice over, since the corpus was reachable and now says something
  specific.
- **An era caveat is attached to front-loading, and it is load-bearing.** The
  cited post is from 2024 (v3/v4). `help.suno.com` 5782849 says of v4.5 that
  *"In previous models, you would want to prioritize certain genre and style
  details, but your instructions can now include a more conversational prompt."*
  First-party guidance is moving **away** from the terse prioritized-token style
  the rule describes. So front-loading is attested for terse comma-separated
  prompts and **unverified for the v5.5 conversational prompts this skill
  targets**. Rating it without that split would have shipped a v3-era finding as
  current advice.
- **Middle-tag softening (roughly 4-7) stays unsourced**, explicitly. The post
  that sources the first half says nothing about middle positions, and the entry
  now warns against letting one half carry the other.
- **`SKILL.md`'s MEDIUM rung records the browser route to Reddit**, so the next
  reader does not rate a third claim down for a corpus that is open.

## [1.1.3]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226.** No reading, no new unit, no new technique.

**This release repairs 1.1.2, which shipped with two review findings
outstanding.** Both were raised on PR #2351 and both were correct; the PR was
merged before the fixes were pushed, so they land here instead. Nothing in the
1.1.2 entry is rewritten — it records what shipped, including what was wrong
with it.

### ⚠ 1.1.2 REPLACED AN OVERCLAIM WITH AN OPPOSITE OVERCLAIM

1.1.2 correctly removed *"Order encodes priority"* from `power-tips.md`. It then
asserted the negative: *"Grammatical role, not word position, is what the sources
describe as the signal."* **The evidence does not carry that either.** The one
source that addresses order says word order matters *"not just"* on its own —
which treats position as a **contributing** signal, qualifying the positional
rule rather than refuting it. The other two speak only to hierarchy and say
nothing about position at all.

**Position is not ruled out. It is unestablished.** The section now says exactly
that. This is worth stating loudly because the failure is subtle and repeatable:
an audit that correctly finds a claim unsupported is *not* thereby licensed to
assert its opposite. Both directions need evidence, and a confidently-worded
demotion reads as researched while carrying the same defect the demotion was
meant to fix.

### Fixed

- **The genre-fusion section no longer claims MEDIUM confidence**, because it
  never met this skill's own bar. `SKILL.md`'s ladder defines MEDIUM as multiple
  community guides **plus** Reddit consensus — and 1.1.2 recorded in the same
  breath that the Reddit pass could not run (the search tool available refuses
  `reddit.com`). So 1.1.2 routed callers to a confidence level its evidence had
  not earned, using the very ladder that release proposed as the governing home
  for Suno claims. The section now states that it sits **between LOW-MEDIUM and
  MEDIUM**: three independent guides clearly exceed LOW-MEDIUM's "at most a
  single community post", and the Reddit half of MEDIUM is unmet and untried.
  **No new rung was invented** to make the claim fit — the gap is named instead.
  `SKILL.md`'s router row matches.
- **An r/SunoAI pass is added to the genre-fusion recheck trigger**, since it is
  now the specific event that would settle the rung in either direction.
- **`tips.md` stated the same conclusion twice within six lines.** The `Effect:`
  line and the corpus block both explained that the `~70%` had no basis; the
  `Effect:` line now points down to the corpus instead of restating it.
- **`SKILL.md`'s LOW-MEDIUM bullet had grown to a ~150-word sentence-run**
  covering two unrelated items (the `voices.md` caveats and the timing-cue
  history). Split into two sub-bullets under the same rung.

### Process note worth keeping

The two findings above were posted as review threads on #2351 and the PR merged
before they were addressed. **A merged PR is not evidence its review was
resolved** — check the thread state, not the merge state, and when a merge
outruns a fix, ship the fix as its own release rather than editing the shipped
entry to hide the gap.

## [1.1.2]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226**. No Pattison reading was done and no unit was opened. This
release closes issue #2266 — the two unaudited Suno claims 1.1.1 left flagged —
by **sourcing one and deleting the number behind the other**, and sweeps two
sibling sites of the same claims that #2266 did not name.

**A patch, not a minor.** No technique is added or removed. Every change either
attaches a source to a claim already here, corrects a stated mechanism, or
deletes a figure nothing supports.

### ⚠ A FIGURE SHIPPED SINCE BEFORE 1.0.0 HAD NO BASIS — `~70%` timing-cue adherence is deleted

1.1.1 recorded that the timing-cue entry's `~70%` had no basis **in this repo**
and left it flagged `LOW-MEDIUM` rather than removing it. That was half the
work: an unsourced figure marked low-confidence is still an unsourced figure,
and a percentage is the most quotable thing in a file. It was searched
externally this release and **still has no basis** (corpus below), so it is gone.

**The technique survives; only the magnitude dies.** `[at 0:15 vocals enter]` is
still offered as a secondary nudge behind structural tags — nothing found
contradicts it, and #2266's standing rule for unsourced-not-contradicted claims
is keep-and-mark. What could not be kept is a number pretending to be a
measurement.

### Fixed

- **`power-tips.md` genre fusion: the mechanism was wrong, not just unsourced.**
  The section asserted *"Order encodes priority"*. Three community guides,
  fetched verbatim on 2026-08-12, attest a **hierarchy** — one anchor genre plus
  one accent, never equal billing — and one of them states the opposite of the
  positional reading: *"The cleanest way to signal hierarchy is through sentence
  structure, not just word order."* The section is rewritten as **anchor and
  accent**, at **MEDIUM** confidence with all three sources quoted, a fetch date,
  and a recheck trigger. The file's own example never isolated order in the first
  place — `synth-pop with dream-pop textures` changes grammatical role *and*
  position at once — and now says so.
- **The "hard cap: 2 genres" was this file's own sharpening.** Two sources model
  exactly one anchor plus one accent and a third warns against "three-way
  competition", but **no source states a numeric cap**. Reworded to two as the
  working default, with three-or-more needing an explicit hierarchy.
- **`genre-taxonomy.md:471` carried `~60% of descriptor weight`** for the same
  fusion claim — a second invented figure, in a file #2266 never named. No source
  states a percentage split. Deleted; the row now points at the sourced section.
- **`lyrics.md:208` carried the `~70%` too**, in a technique table. Same
  treatment as `tips.md`, so the two cannot drift apart again.
- **`power-tips.md`'s blanket header claimed the file was
  "community-validated through empirical testing".** Two sections inside it are
  explicitly flagged unverified, so the header asserted validation the file
  cannot back — the exact intra-file inconsistency #2266 was filed about.
  Replaced with a per-section rule: an unflagged section has not been audited.
  `SKILL.md`'s router row, which still advertised the whole file as MEDIUM-HIGH,
  is corrected to match.

### The corpus searched, so the next reader need not redo it

Every absence below is **scoped to the pages named** and asserts nothing about
Suno's documentation as a whole.

- **Official, read verbatim by `curl` (not a summarizing fetch), bodies whole:**
  `help.suno.com` [5782849](https://help.suno.com/en/articles/5782849) (1,177
  chars of extracted text) and
  [5782977](https://help.suno.com/en/articles/5782977) (805 chars). Neither
  addresses genre order or fusion; neither mentions timestamp cues in the Lyrics
  box or any adherence rate. 5782849 points *away* from positional prompting for
  v4.5+: *"In previous models, you would want to prioritize certain genre and
  style details, but your instructions can now include a more conversational
  prompt."*
- **Community, for the timing cue:** the two largest public meta-tag references —
  Jack Righteous' Suno meta tags guide (22,687 chars) and Blake Crosley's v5.5
  guide (93,464 chars) — carry **zero** occurrences of a `0:1`-style timestamp
  cue and **zero** of `70%`. Jack Righteous routes timing problems out of the
  prompt entirely, to Studio or a DAW.
- **r/SunoAI could not be searched** — the search tool in this environment
  refuses `reddit.com`. The community corpus above is therefore guides only, and
  a Reddit pass remains undone.

### Scope note — `docs/conventions/upstream-drift/` was read and deliberately not adopted

That convention's required parts (claim, basis, as-of date, recheck trigger) are
what the two sourced records above are shaped on, and it is cited here as the
precedent. It is **not** claimed as the owner of this class: its fetch-route
ladder, its `llms.txt` identity check and its drift signal are all specific to
`code.claude.com`, and none of that transfers to an Intercom-hosted help centre.
Suno claims stay governed by **the confidence ladder in
`skills/suno/SKILL.md`**, which already carries source-quality semantics; what it
lacked, and what this release borrows from the convention, is the **recheck
trigger**. Adding a row to that convention's adopters table is out of this
plugin's scope and was not done.

### Still open

- `power-tips.md` "Tag order" (`:7-13`, demoted in 1.1.1) is **still unsourced in
  either direction**, and this release did not search for first-tag advantage or
  middle-tag softening. #2266 asked that `:7-13` and the fusion claim be taken
  together; they can no longer be resolved on one body of evidence, because the
  fusion claim is now sourced and the tag-order rule is not.

  **But the fusion pass turned up a first-party lead worth handing on, so it is
  not lost.** `suno.com/hub/how-to-make-beats`, fetched 2026-08-12, says: *"it
  reads prompts as structured instructions. A clear hierarchy matters … A strong
  prompt follows this order: tempo, genre, rhythm style, instruments, and
  mood."* A community guide echoes the shape — sunopromptpro: *"A practical
  pattern is primary genre, secondary production influence, vocal direction,
  rhythm detail, and section structure."* **This is a lead, not evidence.** Both
  prescribe an ordering of descriptor *categories*, and the hub page is scoped to
  beat-making; neither says a first tag carries more weight or that middle tags
  soften, which is what `:7-13` actually claims. A future tag-order audit should
  start here and must not mistake the two for the same claim.
- The ledger both #2233 and #2266 cite as authority,
  `.work/songwriting-plugin-pilot/suno-drift/RESEARCH.md`, **does not exist** —
  not in the working tree, not anywhere in git history, and not on disk. Every
  "no audit row covers this" claim resting on it is unfalsifiable as written.

## [1.1.1]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226**, read from the ledger rather than inherited. Nothing here
opens a new unit — no new reading was done. This release closes the six
follow-ups tracked in issue #2233.

**A patch, not a minor.** The one piece of new content is a lyric this project
had itself recorded as a deliberate omission, so restoring it is a fix rather
than an addition.

### ⚠ A CLAIM SHIPPED IN 1.1.0 WAS FALSE — figure `34F` is NOT image-only

1.1.0 recorded, under "Known and deliberate omissions", that fig
`image_rsrc34F`'s five-line lyric was *"image-only — absent from the gated 1991
text layer, confirmed against a known-present control"*. **It is not.** The same
verse is printed as prose in the 1991 spine, in **Chapter 1** — six chapters
before the figure, which is in Chapter 7. The original search was scoped to the
spine file holding the figure and never asked whether another chapter printed
it.

**The control could not have caught this, and that is the lesson.** A grep for
line five — `make everything so clear` — returns **zero across all four books**,
because the 1991 text layer prints `averything`. A known-present control proves
your *search* works; it can never prove your *target* is absent. One line failing
where its neighbours match means "look for a typo", not "absent".

### Added

- **Fig `image_rsrc34F`'s five-line lyric is transcribed** in `hook.md`, with
  its scansion. Every row was read one row at a time at **12-13x**, by eye,
  **no OCR**, from named PNG files. Rows 1-4 carry 5, 5, 5 and 3 slash marks;
  row 5's
  doubled mark is recorded exactly as printed, still without deciding whether it
  denotes two stresses or is a printing anomaly.
- **A standing rule for image-only figure content**, in `book-references.md`:
  render, read by eye, name the PNG, **OCR forbidden**, crop one row at a time.
  This is not a new practice — it is what `hook.md` (fig `34G`), `cliche.md` and
  `bridge.md` already do. Fig `34G` proves it: the figure prints `ANYMORE`, the
  prose prints `ANY MORE`, and `hook.md` correctly prints the figure's form.
- **The `Challenge #N` boundary**, in `book-references.md`, as a role table.

### Fixed

- **50 bare `Chapter N` / `Challenge N` citations now name their book.** Each
  book was resolved by matching the introduced block against the four spines,
  under a control that fails the run if matching breaks. **One site was genuinely
  ambiguous** — the `wind = yelping dog` drill is printed in *both* the 2009 and
  2011 books — where the previous measurement had reported none; only the chapter
  number settles it, since the 2011 book has Challenges and Days, never chapters.
  The last **3** of the 50 came from re-running the scan with a deliberately
  looser pattern and diffing it against the tight one: the tight scan required
  the intro line to end in a colon and the block to be quoted or fenced, and so
  was blind to indented blocks and to intros that trail into the next sentence.
  Loose found 9 more sites, **6 false positives** — four inside HTML comments,
  one a sentence of this release's own new prose, one a plugin-authored example
  inside a fence — and **3 real ones**, now fixed.
- **`rhyme-types.md` attributed the wrong chapter.** The `travel` family search
  is printed twice: Chapter 4 annotates `glass full (mosaic)`, and Chapter 6
  recalls the search and drops the annotation. The reproduced block is
  **Chapter 6's** printing, followed by Chapter 6's "Add partial rhyme" move,
  while the line cited Chapter 4. Found by a second check that verified cited
  chapter *numbers* against all 266 spine headings — the resolver itself only
  ever proved the *book*, and would have passed 47 correct book names sitting on
  wrong chapter numbers.
- **10 citation-role `Challenge #N` sites normalized** to `Challenge N`. Exactly
  one hash site remains in the research corpus — `metaphor.md`, inside a
  quotation, verified verbatim against the 2011 spine. The other occurrences in
  the plugin are the new rule in `book-references.md` and this changelog, both
  of which quote the form in order to describe it.
- **`lyrics.md` no longer claims first-party support it does not have.** The
  cited Suno article is "How to Use: Song Editor" and contains no bracket-tag
  content. The false clause was deleted and **no citation was substituted for
  it** — the surviving `HIGH` is re-anchored to the community attestation that
  actually carries it.
- **`advanced.md`'s `Wrong (silently ignored)`** is now `Off-convention`. No
  source shows negation phrases failing; the bare-noun form is the attested one,
  which is a different claim.
- **`power-tips.md`'s positional tag weighting** moved out of instruction bullets
  into prose marked never-checked. **No audit row has ever examined this claim
  class**, so it is kept and marked rather than deleted — unsourced is not
  contradicted.
- **`voices.md`'s privacy warning now governs every voice creation**, not just
  the subsection for writers who cannot sing. A competent singer never read it
  before.
- **`SKILL.md`'s confidence ladder gained the `LOW-MEDIUM` rung** that two files
  were already using without it being defined.

### Recorded, deliberately not resolved

- **Fig `34F` against the prose printings.** The figure drops the `that` in line
  one; Chapters 4 and 6 keep it. Figs `34F` and `32V` print `everything`; the
  Chapter 1 text layer prints `averything` — the only occurrence in the corpus,
  confirmed genuine to the EPUB. Two photographs of the printed page against one
  reflowed text run, so **the text layer carries the defect**. This is the one
  site where a figure adjudicates the spine. `phrasing.md` carries a note so a
  future spine-matching sweep cannot "restore" it.
- **`voices.md`'s account-locked line versus the reported default-public
  toggle.** Both are stated, the conflict is stated, and the conservative reading
  governs. No reconciliation was invented, and the warning is **not** described
  as disputed — the poster re-affirmed it and nobody rebutted it.

### Still open

<!-- spellchecker:off -->

- **`melodic-software/standards#349` is MERGED**, but `_typos.toml` here has not
  synced — `DUM` is still absent. The 56 inline `<!-- spellchecker:off/on -->`
  guards stay until it does.

<!-- spellchecker:on -->

- `power-tips.md:29` ("Order encodes priority") is the same never-audited claim
  class as the rule demoted above, in the same file, and no audit row covers it.
- The `tips.md` timing-cue entry's `~70%` figure has no basis recorded anywhere
  in this repo. Flagged `LOW-MEDIUM` and left flagged.

## [1.1.0]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226.** Nothing here opens a new unit. This release closes six
sourced Suno remediations that a previous session left blocked, records the
first r/SunoAI thread ever read for this plugin, and settles the buy-the-books
title convention.

### ⚠ PUNCTUATION GLYPHS ARE NOT A FIDELITY AXIS — DO NOT SWEEP FOR THEM

**Verbatim means the words.** Apostrophe and quote *glyphs* — ASCII `'` `"`
versus curly `’` `“` `”` — are not part of it. This repo is GitHub-flavored
Markdown and either form is fine.

Much of this session went into normalizing curly punctuation across 470 lines in
31 files. The owner ruled it out of scope, and the review gate then found it had
left **20 paragraphs with mismatched pairs** — a curly opening quote closing
against a straight one, because the sweep matched line by line and quotations
wrap. That is worse than what it replaced. **The entire change was reverted**;
those 31 files are byte-identical to the previous release.

**No future session should measure, sweep, audit, or report on this class.** The
standing rule now lives at the top of `book-references.md`, where the citation
convention is read.

The correction that does matter: during that work two earlier receipts (`V1`,
`V7`) were recorded as "refuted on fidelity". **That was wrong — they were
correct.** Their restorations reproduce the source's *words* exactly, which is
the standard that actually applies. **All ten re-verified receipts were sound.**

### Fixed

- **Six sourced Suno remediations closed.** The `suno-drift` audit recorded
  findings S3, S7, S8, S9, G3 and G7 against sites that a previous session
  declared **BLOCKED** because they sat outside its exclusive write-set. Nobody
  picked them up, so the skill has been contradicting itself since:
  - `troubleshoot.md` asserted **silent truncation** as a mechanism while
    `SKILL.md` and `style.md` said it is unverified. Now hedged to
    attention-decay, matching its siblings.
  - `troubleshoot.md` said the title has **no effect** on musical output while
    its siblings said "minimal or no known effect; community reports differ".
    Now softened to match — the best source says *minimal*, and minimal is not
    zero.
  - `power-tips.md` and `troubleshoot.md` presented **negatives-at-the-end** as
    an adherence rule via a "last tag = highest exclusion weight" mechanism. No
    source establishes it; both now present grouping as an organizational
    convention, matching `style.md` and `SKILL.md`. The `no X` syntax itself is
    attested and was left alone.
  - `lyrics.md` described `(text)` parentheticals as **never sung**, which the
    same file already contradicted eleven lines earlier. Now carries the length
    bound; the attested delivery-modifier mechanism is kept.
  - `lyrics.md` listed **`[Fade In]`** inside a HIGH-reliability set although no
    source states it. Marked unattested at both sites. **Kept, not dropped** —
    the audit's row says "drop" but its own summary groups it under "soften",
    and its neighbouring row establishes that unsourced is not the same as
    contradicted. The file's existing `[Synth Solo]` handling set the precedent.
  - `v55-features.md` listed eleven **best-supported languages** where only
    seven are sourceable. All eleven are retained; German, Italian, Russian and
    Arabic are marked unsourced. They are unsupported, not disproven, and the
    audit's explicit warning against "repairing" the list from an availability
    table (that column is Bark-v0 availability, not a quality tier) was obeyed.

### Added

- **A two-stage voice-clone bootstrap for non-singers**, in `voices.md`, from
  **the first r/SunoAI thread this plugin has ever read.** Record 30-60s of
  ordinary speech, save it as a voice, generate a short a cappella test with it,
  then build the voice you actually keep from the *sung* part of that output.
  Reported test-stage sliders and the reported failure mode are included.

  Tiered **LOW-MEDIUM: one post plus its comment thread, not consensus**, and
  labelled untested. Also recorded, as an unverified and *disputed* community
  report, that the "make this voice public" toggle may default to on — with the
  reader told to check it rather than trust either side.

  This does not contradict the file's existing "sing actual melodies, not spoken
  word" rule; the speech clip is scaffolding and the kept voice is still built
  from sung material. That reconciliation is stated in the file rather than left
  for a future reader to trip over.

### Changed

- **`workflow-recipes.md` no longer says r/SunoAI is unreachable.** It was
  reachable all along — search and direct fetch fail, but a browser session
  reaches it, and navigating to the `.json` form of a thread URL is what yields
  the body. The note now records the working route, and states plainly that
  **nothing found there bears on the Cover-harmony question**, so that
  documented-absence finding still rests on the community guides and first-party
  silence. It was not strengthened by a thread that does not address it.
- **The buy-the-books list in `README.md` now carries all four full titles.**
  The 1991 entry used its full title and the 2014 entry its short name; 2009 and
  2011 are unaffected because their short and full titles are identical. The
  list's purpose is purchasing, and a full catalogue title is the one thing a
  short name cannot do, so the 2014 entry was expanded rather than the 1991 one
  shortened. `book-references.md` now names **both** places a full title
  legitimately appears and why — its previous wording implied the bibliographic
  table was the only one, which would have invited a future agent to normalize
  the README and undo this.

### Notes

- **Exactly one file under `context/pat-pattison/research/` changed in this
  release: `book-references.md`,** and its change is prose — the standing guard
  on what verbatim covers, plus the buy-the-books title exemption. The other 31
  are byte-identical to 1.0.2. (`audit-checklist.md` was briefly touched by the
  punctuation sweep and is back to its previous state; the sweep was reverted in
  full.)
- Follow-up work is tracked in **issue #2233** — one owner decision (image-only
  lyrics) plus five mechanical items. This release deliberately closes none of
  them.
- The **2011 book prints `Challenge #1` through `Challenge #4` with the hash**,
  including in its chapter titles. The plugin's citation convention drops it
  (168 occurrences) and ten sites keep it. Both were left as they stand: this is
  a convention question for the maintainer, not a fidelity defect, and nothing
  was changed on the strength of a guess.

## [1.0.2]

Both audit denominators are unchanged: **Axis 1 stays 44 of 44** and **Axis 2
stays 226 of 226.** Nothing here opens a new unit. This release restores content
inside units that were already audited and closed, settles two open maintainer
decisions, and normalizes the plugin's own citation convention.

### Added

- **The 2014 Preface, restored verbatim.** Spine 009's scope, audience,
  exercise/reference workflow and rhyming-dictionary requirement were absent
  from the plugin although the unit was closed. Restored to
  `rhyme-fundamentals.md` at **204 of 204 words**, byte-exact, with a codepoint
  census matching the source (U+2014 x1, U+2019 x6). Both italic runs — the
  purpose clause including its final period, and the dictionary title with its
  following comma *outside* the italics — were confirmed by rendering the page
  scan. This book carries **no `<i>`/`<em>` tags and no `font-style` in its
  CSS**, and wraps every word in its own `<span>`, so the scan is the only
  authority for emphasis. An earlier proposal to paraphrase this passage was
  rejected.
- **Chapter 7's Strategy 5 demonstration, restored to `hook.md`.** Chapter 7
  emits 27 figure markers; the file cited 22. The five uncited figures were
  proven read-only before any writer was dispatched, and four sit at
  dangling-colon sites, meaning the content exists only in the image. The
  `34D`-`34G` worked demonstration and the `34T` resolving scan are now present,
  each transcribed from a rendered figure read directly. **OCR was forbidden
  explicitly**, after a previous attempt's 141 OCR-derived lines were discarded.
- **A prompt-side harmonic technique for Suno**, surfaced by re-running the
  Cover/harmony research with real search budget: key plus mood in the Style
  field, and bracketed chord tags in Custom Mode's Lyrics field — recorded with
  its named failure mode (the model sings the chord names as lyrics) and its
  stated limits, and scoped explicitly to general generation rather than Cover.

### Changed

- **Suno voice-clone protocol consolidated on the single varied 90-120s clip.**
  `v55-features.md` and `tips.md` advised three separate clips; `voices.md` and
  `power-tips.md` advised one. The single-clip side is the only one that supplies
  a mechanism, so it wins. Marked community-derived — Suno publishes nothing
  either way on clip count or length — and each file now records that the 3-clip
  advice was **retired deliberately**, so it does not regrow.
- **Citations normalized to the short title and plural chapter ranges.** Ranges
  read `Chapters N-M`. Where a file quoted its own citation string back at
  itself, both halves were changed together so no self-reference dangles.
- **`book-references.md` no longer contradicts itself.** Its opening paragraph
  said the full title appears in file headers. After normalization that is false,
  and it is a regrowth vector — a future agent reading it would re-expand every
  header. The full title now lives where it belongs: this file's bibliographic
  table.

### Fixed

- **`hook.md` no longer over-claims figure `image_rsrc34F`.** It described the
  fifth row as "3 stresses". The scan prints a **doubled slash** there, and
  whether that denotes two stresses or is a printing anomaly cannot be
  determined from the figure. Row five is recorded as printed, `u u / u // u /`.
- **A removed anti-regrowth note was restored to `prosody.md`.** One agent moved
  out a note that names a specific fabrication — an invented three-item trigger
  list — and whose first sentence is a substantive statement about the source,
  not revision narration. That removal was overturned.
- **Two expanded-title citations in `stable-unstable-meta.md`** that every
  single-line grep had missed, because they wrap across lines.
- **The last surviving 3-clip instruction**, in `troubleshoot.md`. The
  consolidation missed it because the search pattern used to find the D2 sites
  looked for "three clips" and "3 separate clips" but not the bare "3 clips".
  A user hitting a voice-clone problem was still being sent back to the retired
  method. Found by the PR review gate; a broad re-search now returns zero.
- **`hook.md`'s `(balancing position)` annotation reconciled, not deleted.**
  Figure `image_rsrc34D` really does print that label, and the file's audited
  `Strategic position` note is also right that Pat's prose never names it as a
  second position. Both are true, so the transcription stays verbatim and a
  sentence now records the tension — altering transcribed source text to fit a
  claim elsewhere is the fabrication this project exists to prevent.

### Verification

Ten build agents and three independent refuters ran, each with an exclusive
write-set. Counts summed from the receipt headers by script, not from memory:

- Build agents: **53 CONFIRMED, 2 REFUTED, 1 UNPROVABLE, 2 INCOMPLETE-RESTORATION.**
- Refuters: **32 UPHELD, 0 OVERTURNED, 3 NEW DEFECTS.**

The refuting pass found real defects in this session's own work for the fourth
session running. Two are fixed above; the third is disclosed below.

**Known and deliberate omissions.**

- Figure `image_rsrc34F`'s printed lyric is **not restored**. It is image-only —
  absent from the gated 1991 text layer, confirmed against a known-present
  control — so the mandated "splice from the spine, never place lyric text in a
  tool request" method has no source to splice from. The file says so in place.
- Reddit / r/SunoAI **remains unread**; the Suno re-run read community guides and
  wikis, not forum threads. `workflow-recipes.md` records that the avenue is
  still open rather than implying it was exhausted.
- `templates/audit-checklist-prompt.md` received a correct plural-range fix
  although the session's own brief forbids touching `audit-checklist*.md`. The
  change is right and is kept deliberately; the scope violation is disclosed
  rather than quietly retained.

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

- **The highest-volume confidence error in the skill.** One line stamped "Creative
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
