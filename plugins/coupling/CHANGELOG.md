# Changelog

All notable changes to the `coupling` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.3]

### Fixed

- **`reduce`'s coupling model has a working table of contents.** Its `## Contents` section listed
  all six headings as plain bullets with no links at all, so a reader of a 130-line reference could
  see the sections but not jump to one. Each row now links its heading and keeps the descriptive
  gloss as a when-to-read cue. Found while validating the sweep's table-of-contents pass, not by the
  audit itself. Docs-hygiene sweep, L2-progressive-disclosure.

## [0.1.2]

### Changed

- **Instruction-surface de-slop (#2891, coupling cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.

## [0.1.1]

### Changed

- **`reduce`: the hand-off table and its two prose chains name the Skill tool (#3002).** The
  `When | Then` table gains a one-line preamble stating that every skill in the `Then` column is
  invoked via the Skill tool; the PR step (`/source-control:pull-request create`) and the
  design-exploration hand-off (`/architecture:improve`) say so inline, as does the route-lane
  filing arm (`/work-items:track add`) in the same sentence as that hand-off — the table's
  preamble does not reach it, since it is prose outside the table. Wording only; presence
  gates and fallbacks unchanged.

## [0.1.0]

### Added

- `reduce` skill: iterative coupling reduction at four altitudes (docs, code, application,
  repository) — model-typed scan with a verification gate, two-lane partition (safe
  behavior-preserving reductions applied under a scope budget; cross-file and architectural
  candidates surfaced and routed, never auto-applied), and a durable per-repo ledger via the
  topic-docs memory tier so successive runs resume instead of restarting.
- `reference/coupling-model.md`: the assessment model — change-centric coupling definition,
  structured-design strength ladder, connascence (strength × degree × locality), volatility
  weighting, per-altitude mechanisms, and the not-a-finding list.
- `reference/remediations.md`: mechanism catalog (dependency injection, owned interfaces at
  volatile boundaries, configuration externalization, events/mediator, single-source-of-truth
  pointers, published contracts) with an explicit over-abstraction counterweight per entry.
- Topic-docs binding (`reference/topic-docs.md`) for the repo-scoped coupling ledger.
