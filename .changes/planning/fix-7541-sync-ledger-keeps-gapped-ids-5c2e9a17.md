---
bump: patch
---

### Fixed

- `round.sh sync-ledger` and `add-round --sync-ledger` keep each register row's `Q<N>` when the ledger's register ids already have gaps, such as Q1-Q200 then Q500-Q522. They no longer renumber the rows Q1..Qn with the old id moved into a `[Q<old>]` resolution prefix, so records that cite those ids still name the same question. A ledger with no gap, an export with no ledger, and a set holding any id that is not `Q<N>` are numbered as before.
