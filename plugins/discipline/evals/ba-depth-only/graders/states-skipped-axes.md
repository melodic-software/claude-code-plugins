---
type: llm
arm: with-only
focus: last_message
---

Judge the reply's final message.

PASS only if the reply says that the Altitude and Range axes (the bigger goal, and other fields) were skipped, and gives a reason, such as the user asking for depth only.

FAIL if it lists Altitude or Range as applied, or does not say they were skipped.
