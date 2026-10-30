---
type: llm
arm: both
---
PASS only if the CSS sets the body's `font-family` to the platform's system font stack (`system-ui`,
or a stack led by `-apple-system`, `BlinkMacSystemFont`, `"Segoe UI"` and similar platform faces,
ending in `sans-serif`), or to a typeface the platform does not ship (Inter, Geist, IBM Plex Sans)
for which the reply states a reason specific to this app (for example tabular figures for stock
counts), not taste alone. FAIL if it loads or names such a typeface with no reason, or with only a
generic one ("modern", "clean", "looks better"), if it sets no `font-family` for the body, or if the
reply contains no CSS.
