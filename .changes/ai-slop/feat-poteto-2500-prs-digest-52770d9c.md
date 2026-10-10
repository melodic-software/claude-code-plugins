---
bump: minor
---

### Added

- **Two rubric tells: `rule-over-compression` and `rule-figure-for-fact`.** Over-compression
  reports prose for people cut so short that the reader cannot tell what team shorthand stands
  for, how two steps connect, what a symbol means, or which thing is meant and who acts; tables,
  references, code, commit subjects and terse agent-facing instruction lists are out of scope.
  Figure-for-fact reports a comparison to an unrelated scene, a consequence told as a small
  drama, a program credited with moods, or a slogan, where a literal sentence of about the same
  length would tell the reader more; a sentence whose only figure is a noun listed by
  `rule-abstract-metaphor-jargon` goes to that rule. The rewrite guide gains a fix for each, and
  the catalog's general-prose additions count is 9.

### Changed

- **The README, catalog and rewrite guide no longer point at the upstream ledger.** The
  provenance line in each is removed; where the general-prose additions came from is recorded only in the
  marketplace's `docs/upstream/` pages. The rewrite guide's note on the left-out voice technique
  now says not to re-add it.
- **Rewrite guide and catalog reworded in their own terms.** The plain-speech questions and the
  phrase replacements are tables with this repository's own examples, and the voice techniques
  are grouped by where they apply. The colon-crutch, stacked-hedge and inline-header examples are
  new; the false-range entry is reworded around its unchanged example. The catalog section that
  holds the chat-residue, filler, hedging and other general-prose tells is renamed
  "General-prose additions" (anchor `#general-prose-additions`; update any link to the old
  anchor), and the detector test fixtures for those rules are renamed to match. No rule,
  threshold or rule id changed. The README, catalog and guide record where that section's tells
  came from by pointing at the marketplace's upstream ledger.
