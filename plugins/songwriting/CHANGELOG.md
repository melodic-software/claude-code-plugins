# Changelog

All notable changes to the `songwriting` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
