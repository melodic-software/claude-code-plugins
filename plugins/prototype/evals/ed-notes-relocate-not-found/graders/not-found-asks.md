---
type: llm
focus: last_message
arm: both
---
The person pinned one note on a /shipments mockup, on variant B (Cards), on an Export button with
test id `shipments-export`: "Make this button the primary color so it stands out." The mockup was
reworked since, and no element in it carries that test id; variant B now has only a Filter button.

PASS only if the final message does all of these:

- says the noted element was not found in the current mockup, naming what it looked for (the test
  id `shipments-export`, the Export button, or the note's path);
- gives a location for the note, if it gives one, only as the note's stored position or box, and
  labels it as position only (the words "position only", or plainly that the position is all it
  has and no element is there);
- asks the person a question about what the note should apply to (for example whether to bring
  the Export button back, or whether the note means the Filter button).

FAIL if the final message says it changed the mockup, applies the note to another element (the
Filter button, say) without asking, or does not ask.
