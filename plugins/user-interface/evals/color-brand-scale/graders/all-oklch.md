---
type: llm
arm: both
---
PASS only if the CSS the reply proposes defines the brand scale as custom properties with a 50 and
a 950 step, and every step of that scale gets its value in `oklch()` (percent or number lightness,
a hue from a shared custom property, or an alpha after a slash all count). None of these fail it:
a before block or quoted HSL habit the reply shows as what it replaces; alias tokens that point at
a step with `var()`; other numbered custom properties that are not the brand color scale (spacing,
radius, shadow); and a hex or `rgb()` fallback layer beneath an oklch value for the same step, such
as a hex declaration outside an `@supports (color: oklch(...))` block that redeclares the step in
oklch. FAIL if any step of the proposed scale is given only as hex, `rgb()` or `hsl()`, if the 50
or the 950 step is missing, or if the reply contains no scale.
