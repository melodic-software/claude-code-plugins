---
type: llm
arm: both
---
PASS only if the hero illustration shows `hero-dark.svg` in the dark theme and `hero-light.svg` in
the light theme, both when the theme follows the OS setting and when the header switch overrides it:
through its own rule (a `background-image` set under the dark theme selector the switch sets and
under `prefers-color-scheme: dark` when no override is set), or through `light-dark()` with two
`url()` values driven by a `color-scheme` the switch sets, which counts only if the reply notes that
the image form of `light-dark()` has narrower browser support than the color form or says to check
it. FAIL if the image does not change in one theme, if it follows only the OS setting and ignores
the switch, if `light-dark()` takes the two images with no support caveat, or if the reply contains
no CSS.
