---
bump: patch
---

### Fixed

- The interview page no longer takes a decision on an archived or superseded question: its Decide
  choices, Save and Reopen are disabled, Ask, Rephrase and Research this still work, and a primary
  `Go to <id>` button opens the end of its `supersededBy` chain. The page server answers such a
  decision 409 `{"error": "superseded", "by": "<id>"}`, or `{"error": "archived"}`, and
  accept-audit leaves a superseded question out.
- An answer recorded before its question was superseded no longer counts as answered and live in
  the page meter or `round.sh status`: both now read `supersededBy` before the decision, as
  `export-ledger` already did, so they agree with the exported `withdrawn` row.
