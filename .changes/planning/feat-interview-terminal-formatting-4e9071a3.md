---
bump: major
---

### Added

- `questions_per_round` caps how many questions an interview round holds (at most 8, the shared lane included); `citation_links` picks plain, `vscode` or file links for round citations.
- Round titles take an optional topic, and rounds take the No recommendation, Your answer settles, Why, Gains, Costs and Evidence labels.
- The terminal confirmation recap groups answers under Needs your eye, each topic, Changed after you first saw it, and Terms and ADRs, one uncut line per question.

### Changed

- The scope check prints the questions asked so far, records each round's opened and closed counts under `## Round counts`, and suggests `/planning:wayfind` when two rounds in a row open more questions than they close.
- The procedure check fails a ledger with no `## Glossary lookup` line or an answered decision no `## ADR outcomes` line covers.

### Removed

- The `wayfind_suggest_questions` setting and the scope check's `--limit` flag.
