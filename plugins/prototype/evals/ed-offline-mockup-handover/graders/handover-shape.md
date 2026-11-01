---
type: llm
focus: last_message
arm: both
---
PASS only if the final message is a handover that (1) gives a file:// path to the
mockup; (2) lists every variant on its own line with its key, a name describing its direction
(not "Option A" or "Variant 1") and its states; (3) says no screenshots were captured or that
Playwright was unavailable, or pairs each variant with screenshot paths; (4) gives one tradeoff
row or entry per variant saying when it is the right choice and what it costs, without
recommending one as the favorite; and (5) includes a fill-in reply template with direction: and
steal: lines. FAIL if any part is missing, if it recommends a winner, or if it asks the user
questions instead of handing over a built mockup.
