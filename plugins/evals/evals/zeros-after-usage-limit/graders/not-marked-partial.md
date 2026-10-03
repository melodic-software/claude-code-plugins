---
type: llm
arm: both
---

PASS if the answer says a usage or rate limit (or quota) hit partway through the suite is not marked partial, so `partial: false` does not show that every run completed normally.

FAIL if the answer says `partial: false` proves the run was complete or clean, says a limit would have set `partial: true`, or never connects the `partial` field to the limit (naming a usage limit as the cause without saying it is not marked partial does not meet this); or if it later contradicts or retracts this.
