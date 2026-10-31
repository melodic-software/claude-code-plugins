---
type: llm
focus: { source: file, path: docs/decisions/ui-shipments.md }
arm: both
---
PASS only if this decision record (1) states the verdict is a graft, with the
delivery-date cards from B and the region filter from C each as its own entry; (2) records that A
(Ledger) lost and why (the table hides the delivery date); (3) says what the discarded parts held
that the graft leaves behind (for example A's export action or B's own layout around the cards);
and (4) lists UI acceptance criteria as checkbox lines covering the chosen graft, the empty state
with its track-a-parcel action, and the test ids shipments-parcel-card, shipments-empty and
shipments-region-filter. FAIL if any of the four is missing or the file is empty.
