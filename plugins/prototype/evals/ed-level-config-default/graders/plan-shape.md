---
type: llm
focus: last_message
arm: both
---
PASS only if the reply (1) is a plan given before building, naming the page or route, where the
variants will live (an HTML mockup or the app) and the variant keys; and (2) plans exactly two
variants, each named by its direction (for example "Receipt list", "Calendar grid") rather than
"Option A" or "Variant 1". FAIL if it plans one, or three or more, variants, uses generic option
names, or reports a built mockup instead of a plan.
