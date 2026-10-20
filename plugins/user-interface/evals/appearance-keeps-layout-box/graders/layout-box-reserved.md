---
type: llm
arm: both
---
PASS only if the reply's CSS does all three: the number uses tabular digits (`font-variant-numeric:
tabular-nums` or `font-feature-settings: "tnum"`), the number sits in a fixed-width slot (a `ch`
width, `min-inline-size`, `min-width` or another fixed width), and the loading skeleton is sized to the
final layout (the same width and height as the loaded number, not zero or a different size). FAIL if
any of the three is missing, or the reply contains no CSS.
