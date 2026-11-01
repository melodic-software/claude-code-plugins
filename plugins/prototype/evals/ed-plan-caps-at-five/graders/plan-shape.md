---
type: llm
focus: last_message
arm: both
---
PASS only if the reply (1) is a plan given before building, naming the page or route,
where the variants will live (an HTML mockup or the app), the variant keys and the states the
page has; (2) plans no more than five variants and says the count stops at five (or explains
that more would repeat earlier ones); and (3) names each planned variant by its direction (for
example "Comparison table", "Single hero plan") rather than "Option A" or "Variant 1", with the
axis it differs on. FAIL if it plans six or more variants, plans eight without comment, uses
generic option names, or skips the plan and reports a built mockup.
