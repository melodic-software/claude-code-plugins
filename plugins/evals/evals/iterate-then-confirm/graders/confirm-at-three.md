---
type: llm
arm: both
---

PASS if the answer says to confirm a change at 3 runs per case (the default) before believing it.

FAIL if the answer says more than 3 runs per case are needed (for example "3 to 5", 5, or 10), says 3 is not enough, says one run is enough to confirm (iterating at one run before the confirm is fine), gives no run count for the confirm, or later contradicts or retracts this.
