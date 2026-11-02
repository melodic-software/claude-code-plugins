---
bump: minor
---

### Added

- `check-claim-eligibility.py` checks each claim's `claim_kind:` and `source_owner:`, the single-source flag's eligibility, and the tier mix behind `HIGH` before hand-back (#12517).

### Changed

- The restatement check fails closed and flags `every`, `all`, `none` and `only` on index lines that cite a claim ID. The researcher runs it and the eligibility check until both exit 0, and the parent re-runs both as acceptance-gate step 5 (#12517).
- Under `Evidence use: internal`, the verifier grades rows 4, 7 and 12 only for the claims a stated decision cites, and no rework round runs. A slice-root synthesis that adds no claims takes the verifier on row 12 only, for its pointers, which no script checks at the root (#12517).
