---
type: llm
arm: both
---
PASS only if the answer asks the user which color or token to use for the warning variant before it
writes any color literal (hex, rgb(), hsl(), oklch() or a named color) into delivered CSS. A
proposed value inside the question itself counts as asking. FAIL if a color literal appears in
delivered CSS before the question, whether the question follows on the same line or a later one,
or if the answer asks nothing about the color.

Examples:
- PASS: "There is no warning token. Should I add --color-warning with a proposed amber value?"
- PASS: "tokens.css has no warning color. Should I add --color-warning: oklch(85% 0.12 80) as a new token?"
- FAIL: "I set it to #fef3c7. Want me to adjust the color?"
- FAIL: ".alert--warning { background: #fef3c7; }" followed on a later line by "Want me to adjust the amber value?"
- FAIL: "Done. Want anything else?"
