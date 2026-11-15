---
type: llm
focus: last_message
arm: both
---
PASS only if the final message is a handover that (1) gives a file:// path to the
mockup; (2) lists every variant on its own line with its key and a name describing its direction
(not "Option A" or "Variant 1"), and gives the states either on each variant's own line, named
there or referred to there by naming the variant they come from ("same five states as A") once
that earlier variant's line has named them, a sub-bullet directly under a variant's line counting
as that variant's line; or once for all variants, in one line that names the states and says
every variant has them ("Every variant has the same states: ..."). A reference that names no
source variant ("same states") fails (2) unless an earlier variant's line named the states. A
message that names no states, or leaves a variant with neither states nor a named source variant
without saying every variant has the same states, fails (2); (3) says no screenshots were captured or that
Playwright was unavailable, or pairs each variant with screenshot paths; (4) gives one tradeoff
row or entry per variant saying when it is the right choice and what it costs, without
recommending one as the favorite; (5) includes a fill-in reply template with direction: and
steal: lines; and (6) gives, before the reply template, a numbered list of steps for the user to
try on the mockup, each an action with the result to expect, separate from the onboarding
checklist content the screen itself shows. FAIL if any part is missing, if it
recommends a winner, or if it asks the user questions instead of handing over a built mockup.
