---
type: llm
arm: both
---
Expectations: "The answer says this is not kerning, and that kerning adjusts one specific
pair of characters", "The answer says tracking applies evenly across the whole run of text" and
"The answer scopes the change to the uppercase labels rather than all text".

PASS only if the reply says this is not kerning (kerning adjusts one specific pair of characters),
says tracking applies evenly across the whole run of text, and scopes the change to the uppercase
section labels. FAIL if it agrees it is a kerning fix, does not separate the two, or applies the
change to all text.
