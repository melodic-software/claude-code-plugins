---
type: llm
arm: both
---
PASS only if the answer names a typeface pairing: two typefaces or font families (by name, or by
a specific family class such as a humanist sans) and which role each plays or that they pair.
FAIL if it names no typefaces, or if words that are colors or moods are the only thing set next to
each other.

Examples:
- PASS: "Pair a soft serif such as Lora for headings with Inter for body text."
- PASS: "Type: Lora / Inter."
- FAIL: "Palette: Sage / Sand / Clay"
- FAIL: "Calm, muted greens and sand tones."
