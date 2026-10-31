---
type: llm
arm: both
---
PASS only if the reply's CSS defines a numbered scale with a 50 and a 950 step (the steps between
may be any subset) and all of these hold: every
step uses the same oklch hue (numerically equal values such as `277` and `277.0` count as the same,
and so does one shared hue custom property used by every step); an alpha written after a slash
does not matter; and neither the 50 nor the 950 step sits at lightness 0 or 1 (`0%` or `100%`).
FAIL if any step's hue differs from the others, if a step is not written in oklch, if an endpoint
sits at lightness 0 or 1, or if the reply contains no scale.
