---
type: llm
arm: both
---
A CSS transition runs on the timing of the state it moves to, so the menu's entrance takes the
duration that applies while `.account` has `data-open` and its exit the duration that applies
without it; one transition that applies in both states gives both the same duration. PASS only if the
reply's CSS gives the menu's entrance a duration of at most 250ms on an ease-out curve (the
`ease-out` keyword, a custom `cubic-bezier()` that starts fast and settles, or a token the reply
defines that way), the transition or animation lists the properties it animates instead of `all`,
and the exit lasts at most 0.8 of the entrance (the default `animation.duration_ms.exit_factor`).
FAIL if the entrance runs longer than 250ms, if the entrance uses `ease-in` (the keyword, not
`ease-in-out`) or a curve that starts slow, if any transition is `transition: all` or the Tailwind
`transition-all` class, if the exit lasts as long as the entrance or longer, or more than 0.8 of it
(for example 180ms against a 200ms entrance), or if the reply contains no CSS.
