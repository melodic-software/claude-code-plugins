# Changelog

All notable changes to the `naming` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Changed

- **Structured context brief.** The loose "distill a brief" step is now a
  brief with named fields — responsibility, firing/usage context, scope
  boundaries (what it is NOT), collision vocabulary, word-level blocklist
  (with reasons), and rejected incumbents (with reasons) — mirroring the
  replicated concept → word → structure naming model. The generators
  receive this brief, and only this brief.
- **Declared criteria priority.** The fallback general criteria are now
  research-ordered — semantic accuracy (anti-misleading) > scope fit >
  comprehensibility > trigger/evocative utility — and this ordering governs
  scoring and judging. A consuming project's declared conventions still
  override it.

### Added

- **Rejection-reason iteration protocol.** A rejected candidate's REASON is
  captured as an explicit new brief constraint (a word-level blocklist
  entry, a scope-boundary correction, or a criteria reweight) and fed into
  the next blind round; rejected names and words never re-enter.
- **Modality layer.** Criteria split into a universal semantic layer and a
  modality/vendor-specific syntactic layer; documented style conflicts
  (abbreviation policy, acronym casing, casing style) route to the
  consuming ecosystem's own style guide rather than a house verdict. For
  Claude Code skills, the description — not the name — drives discovery, so
  the name optimises for human semantic accuracy.
- **Strengthened domain-concept pointer.** When the target is a domain
  concept, route to a domain-modelling capability to settle what it IS
  before naming it (pointer only).
- **Research grounding.** `context/sources.md` adds the primary empirical
  sources behind the criteria priority (Feitelson TSE 2022, Alpern 2024
  reproduction, Avidan & Feitelson 2017, Hofmeister 2017) and the modality
  layer (clig.dev, Claude Code skills docs, the conflicting style guides),
  and honestly marks paywalled book sources as Tier-2-for-verification.

## [0.1.0]

### Added

- **Initial release.** `/naming:name-it-better` — generate fresh name
  candidates by fanning out blind, fresh-context generators from distinct lenses
  (responsibility-literal, moment-of-use, domain-lore), score a shortlist against
  the consuming org's naming criteria, and recommend — the human always picks,
  never an auto-locked name. Optional `tournament` action adds elimination rounds
  with independent judges for high-stakes, hard-to-refactor names.
- Repo-agnostic: scores against the consuming project's declared naming
  conventions when present, degrading to the general criteria grounded in the
  skill's `context/sources.md` when none is declared.
