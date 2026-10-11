---
type: llm
arm: both
---
PASS only if every color, spacing, radius, easing and duration in the .notice CSS comes from a
custom property defined in src/styles/tokens.css (--color-*, --space-*, --radius-md, --ease-out,
--duration-fast), and the answer defines no new custom property and writes no literal value for
those categories. A 4px stripe width may be a literal, since no token covers it, if the answer says
so. FAIL if it invents a token, writes a literal color, spacing or radius, or ignores tokens.css.
