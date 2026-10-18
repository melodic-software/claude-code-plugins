---
bump: patch
---

### Fixed

- `round.sh sync-ledger` and `add-round --sync-ledger` (and `export-ledger` and `export-brief`) keep each register row's `Q<N>` when every id is a `Q<N>`, gaps included, so a ledger holding Q1-Q200 then Q500-Q522 no longer renumbers Q500 to Q193 and breaks every record that cites it. A set that mixes in a non-`Q<N>` id is still renumbered with a `[<id>]` lead on each resolution (#7541).
