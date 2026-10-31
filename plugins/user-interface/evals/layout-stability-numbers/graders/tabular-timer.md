---
type: llm
arm: both
---
PASS only if the reply's code gives the timer equal-width digits while it stays in the interface
font: `font-variant-numeric: tabular-nums` on the timer's selector, or the Tailwind class
`tabular-nums` on the timer element. FAIL if the code changes the timer's `font-family` to a
monospace face (`ui-monospace`, `monospace`, `font-mono`, a named mono font) as the fix, even when
it also adds `tabular-nums`; if the digits are fixed only through `font-feature-settings: "tnum"`;
if the timer gets a fixed width as the only fix; if `tabular-nums` appears only in prose while the
code does something else; or if the reply contains no code. Prose that names the monospace swap as
the thing to avoid does not fail a correct answer.
