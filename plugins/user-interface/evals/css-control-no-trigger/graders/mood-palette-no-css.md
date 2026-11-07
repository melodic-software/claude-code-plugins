---
type: llm
arm: both
---
Expectation: "The response gives a mood, a palette in words and a typeface pairing without writing
CSS".

PASS only if the reply states a mood, describes a color palette in words, names a typeface pairing,
and contains no CSS (no selectors, declarations, custom properties or style blocks). Hex or color
codes inside the prose palette are allowed. FAIL if the mood or the worded palette is missing, or if
the reply includes CSS.

Examples:

- PASS: "Mood: calm and grounded. Palette: sage green, warm sand, soft clay. Type: Lora headings with Inter body."
- FAIL: "Type: Lora / Inter. `h1 { font-family: Lora; }`"
- FAIL: "Use Lora for headings and Inter for body."
