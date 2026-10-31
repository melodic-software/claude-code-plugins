---
bump: patch
---

### Fixed

- Text fixes in the interview page's exports and question history:
  - A `revise` that changes `checkedAgainst` logs `Revised constraints checked.`, not `Revised checkedAgainst.`
  - A restated `deferred` or `planningOwned` bullet that says only `none` no longer exports as a Deferred questions entry.
  - The `why:` line of a row that a restated constraints or decisions line carries now sits under that line, not as a separate bullet in Constraints.
  - `sync-ledger` leaves a blank line between the rows it writes into an empty register and the text after them.
  - `export-brief` keeps the restated goal's `-` lines (Intent, Vision and the tiebreak) as bullets, so PLAN.md's Goal no longer needs a hand edit after Confirm.
  - The `revise` op row in the interview's surface reference now lists `checkedAgainst`.
