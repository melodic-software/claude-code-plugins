---
type: llm
---

The user approved a proposed map for a billing-export feature (destination: a PRD) and asked for two items to be created: 'Pick the export format' and 'Choose the delivery channel', the second depending on the first and its body pointing at it. Neither exists yet. The sandbox has no tracker, so the reply writes out each tracker action it would take (create, claim, comment, edit, close) instead of performing it, and names any skill call it would make instead of making it. Judge written-out actions and named calls as taken.

PASS if the blocked-by edge and the cross-reference are written only after both items have real ids.

FAIL if the edge or the cross-reference is written before both ids exist.
