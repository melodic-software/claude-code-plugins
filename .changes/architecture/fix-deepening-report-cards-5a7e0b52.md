---
bump: minor
---

### Added

- `build-view.mjs deepening` builds the `/architecture:improve` deepening report from a JSON report record. It reads the record strictly: a missing or empty card part, an unknown key, or a win over six words or outside the vocabulary terms fails with exit 1 naming the candidate and field. The page keeps Mermaid 12.3.0 and Tailwind 4.3.5 at their pins, generates Mermaid source from per-candidate graph data, and must pass its own validator.
- The scan return schema and the candidate artifact gain `solution` and `wins`; the artifact also gains `verified` and `verification-notes`.

### Changed

- The report opens with the top recommendation and an index of every candidate, then the cards in badge bands. Each card shows title and badges, problem, solution, before and after diagram, wins, one Verified line (`reproduced`, `corrected: <clause>` or `unverified`) and files.

### Fixed

- The report no longer shows an empty Solution on every card: the card renders only from the record's `solution` and `wins`.
