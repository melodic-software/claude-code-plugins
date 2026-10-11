---
type: llm
arm: both
---
PASS only if the answer names a typeface pairing: two typefaces, each identified by name or by a
specific class (such as a soft serif or a humanist sans), with a role or the pairing stated. A
generic "serif headings, sans body" passes: the prompt asks for a direction, so two type classes
with their roles answer it. FAIL if it names no typeface or type class, or if the only words set
next to each other are colors or moods.

Examples:
- PASS: "Pair a soft serif such as Lora for headings with Inter for body text."
- PASS: "Type: Lora / Inter."
- PASS: "Serif headings, sans body."
- FAIL: "Palette: Sage / Sand / Clay"
- FAIL: "Calm, muted greens and sand tones."
