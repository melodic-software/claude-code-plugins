---
type: llm
arm: both
---
Expectations: "The answer says adjusting a pair by eye is manual kerning, not optical
kerning", "The answer says optical kerning is automatic and derived from the glyph shapes" and "The
answer names metrics kerning, or the font's built-in pair values, as the other automatic method".

PASS only if the reply says nudging a pair by eye is manual kerning, not optical kerning, says
optical kerning is automatic and derived from the glyph shapes, and names metrics kerning (the
font's built-in pair values) as the other automatic method. FAIL if it agrees with the premise or
misses either automatic method.
