---
bump: minor
---

### Added

- Interview page: a `reply` or `revise` that changes the recommendation must carry the revised alternatives or `keepAlternatives: true` (CLI `--keep-alternatives`), which states the current ones were checked against it; with neither it is refused and nothing is written. `reply` now takes `alternatives` with `rec`, so an answer and a full revision land in one op, and the history line records whether the alternatives were rewritten or kept (#5801).

### Fixed

- Interview page: the Rec choice shows the whole recommendation the user accepts, not only its first sentence; the Accept all list keeps its one-sentence preview (#5815).
- Interview page: the revised-recommendation banner says "Recommendation revised." once (a change with no `why` now stores `revised: true`, and data holding the old fallback sentence reads the same), and shrinks to a "Revised" chip, with Previous kept, once the user has opened the question since its latest revision (#5916).
