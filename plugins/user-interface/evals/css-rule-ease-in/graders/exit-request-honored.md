---
type: llm
arm: both
---
The prompt explicitly asks for an exit that accelerates away. PASS only if the reply's CSS has at
least one transition or animation and either (a) every curve ends slow (`ease-out`, `ease-in-out`,
`ease`, `linear`, no timing function, or a `cubic-bezier()` that ends slow), or (b) the exit uses an
ease-in curve (`ease-in`, or a `cubic-bezier()` that starts slow and ends fast such as
`cubic-bezier(0.55, 0, 1, 0.45)`) and the reply names the trade-off, that it starts slow or reads as
lag. FAIL if the exit uses an ease-in curve without naming that trade-off, or if the reply contains
no transition or animation.
