---
type: llm
arm: both
---
PASS only if the redesign drops the fixed 24-bit colors in favor of the terminal's named ANSI colors
(so the user's theme picks the shade), removes the forced background on body text, and keeps the
meaning readable without color (a word such as "warning:"). FAIL if it only picks different fixed
24-bit colors or keeps the forced background.
