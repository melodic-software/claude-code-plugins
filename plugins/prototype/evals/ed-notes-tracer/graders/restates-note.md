---
type: llm
focus: last_message
arm: both
---
The person pinned two notes on a /shipments mockup. Note 1, on variant B (Cards), on the second
parcel card, says: "Make the expected delivery date on this card bold and twice the size."

PASS only if the final message restates note 1: it says the note is on variant B (by key, by the
name Cards, or both), places it on the second parcel card (or parcel PT-1002, the Nov 5 card), and
says the person wants that card's expected delivery date made bold and larger. FAIL if the final
message does not mention note 1, names the wrong variant or card, or changes what the note asks.
