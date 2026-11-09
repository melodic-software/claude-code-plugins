---
type: llm
arm: both
---

PASS if the answer says the council stops after round 1, that this is a success (not a failure), that it states the reason (the fix was declined), and that no further round runs. Noting that round 1's findings stay on disk for a later fix is fine.

FAIL if the answer says round 2 runs anyway (on the unfixed change or otherwise), that the council applies the fixes itself, that the run fails, or that the council asks again until the operator agrees.
