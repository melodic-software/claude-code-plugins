# Changelog

All notable changes to the `songwriting` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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

Three context files adjudicated against the full text of the chapter each
claims to distill, rather than against the distillation.

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
