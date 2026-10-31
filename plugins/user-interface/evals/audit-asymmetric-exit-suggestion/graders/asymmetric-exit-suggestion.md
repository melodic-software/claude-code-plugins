---
type: llm
arm: both
---
The menu enters in 200ms and exits in 190ms. PASS only if the report flags the exit as too long for
its entrance (it should take at most 0.8 of the entrance, 160ms or less, or the project's
`exit_factor`) and places that finding at Suggestion severity, the lowest. FAIL if the report does
not mention the exit timing against the entrance, if it rates the finding Blocking or Important, or
if it asks the exit to match or mirror the 200ms entrance.
