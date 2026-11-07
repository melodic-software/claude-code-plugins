---
type: llm
arm: both
---
Expectation: "The press transition stays within the press role (160ms at the defaults)".

PASS only if every duration the press effect's transition uses is at most 160ms. FAIL if any press
duration is longer, or the answer has no transition for the press.
