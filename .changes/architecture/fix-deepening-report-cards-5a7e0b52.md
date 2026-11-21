---
bump: minor
---

### Added

- `build-view.mjs deepening` builds the `/architecture:improve` deepening report from a JSON report record. It reads the record strictly: a missing or empty card part, an unknown key, or a win over six words or outside the vocabulary terms fails with exit 1 naming the candidate and field. The page keeps Mermaid 12.3.0 and Tailwind 4.3.5 at their pins, generates Mermaid source from per-candidate graph data, and must pass its own validator.
- The scan return schema and the candidate artifact gain `solution` and `wins`; the artifact also gains `verified` and `verification-notes`.

### Changed

- The report opens with the top recommendation and an index of every candidate, then the cards in badge bands. Each card shows title and badges, problem, solution, before and after diagram, wins, one Verified line (`reproduced`, `corrected: <clause>` or `unverified`) and files.
- The report record requires `scope` and `commit`, and the header names both. `verification` must start with a level, and the header says what that level checked.
- The header legend has one line for each drawing style, badge, dependency category, win term and Verified value the page uses. A dotted arrow is a pointer and a rust arrow is a leak, matching how the diagrams draw them.
- The index adds Verified and Depends on columns, and stacks each row below 600 px so a phone does not scroll sideways.
- Mermaid panels take the width their drawing needs and never scroll inside the card; a graph with no edges is drawn as plain boxes. The `bars` pattern is removed: its 0 to 10 sizes measured nothing.
- When the CDN is blocked, each Mermaid panel shows its edges as text (`A → B`), not its source.
- Muted labels and captions reach 4.5:1 contrast in both schemes.
- Phase 2 drops a candidate that proposes no change.

### Fixed

- The report no longer shows an empty Solution on every card: the card renders only from the record's `solution` and `wins`.
