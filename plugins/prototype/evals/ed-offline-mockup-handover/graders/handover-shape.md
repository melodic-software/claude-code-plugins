---
type: llm
focus: last_message
arm: both
---
PASS only if the final message is a handover that (1) gives a file:// path to the
mockup; (2) lists every variant on its own line with its key, a name describing its direction
(not "Option A" or "Variant 1") and its states, where the states sit on that variant's own line:
named there, or referred to there by naming the variant they come from ("same five states as A")
once that earlier variant's line has named them; a sub-bullet directly under a variant's line
counts as that variant's line. A reference that names no source variant ("same states") fails
(2) unless an earlier variant's line named the states. States given only once for all variants, outside the variant lines ("Every variant
has the same states: ...", a "States:" bullet, the plan line or the key help), fail (2), however
complete the list; (3) says no screenshots were captured or that
Playwright was unavailable, or pairs each variant with screenshot paths; (4) gives one tradeoff
row or entry per variant saying when it is the right choice and what it costs, without
recommending one as the favorite; (5) includes a fill-in reply template with direction: and
steal: lines; and (6) gives, before the reply template, a numbered list of steps for the user to
try on the mockup, each an action with the result to expect, separate from the onboarding
checklist content the screen itself shows. FAIL if any part is missing, if it
recommends a winner, or if it asks the user questions instead of handing over a built mockup.
