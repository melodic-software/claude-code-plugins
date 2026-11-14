---
type: llm
focus: last_message
arm: both
---
PASS only if the reply (1) is a plan given before building, naming the page or route, where the
variants will live (an HTML mockup or the app) and the variant keys; (2) plans more than three and
no more than five variants for the page, each named by its direction (for example "Sectioned
form", "Sidebar tabs") rather than "Option A" or "Variant 1"; and (3) lists among the planned
states a narrow-viewport, phone-width or responsive state besides the page's ordinary states (such
as populated, empty, loading or error). FAIL if it plans three or fewer, or six or more, variants,
uses generic option names, plans no narrow-viewport or responsive state, or reports a built mockup
instead of a plan.
