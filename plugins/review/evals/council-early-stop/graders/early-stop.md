---
type: llm
arm: both
---

PASS if the answer says the council stops after round 2, as a success, because the round added no new CRITICAL or IMPORTANT finding and none is unresolved; no fix pass runs and round 3 does not run. Mentioning that the SUGGESTION findings stay in the report for a later fix the user starts is fine.

FAIL if the answer says a fix pass runs on the suggestions, that round 3 runs because rounds remain, that the run fails, or that the loop always uses every configured round.
