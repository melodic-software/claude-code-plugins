---
type: llm
arm: both
---

PASS if the answer says both:

1. Do not post the delta: an INVALID verdict means reporting INVALID with its reasons and no score or delta. Referring to the figure without its value ("the delta", "that number", "it") meets this.
2. Fix the cause and rerun before any number is reported.

FAIL if the answer states the delta's value anywhere (as `+0.30`, `0.30`, `0.3`, `.30` or in words), including while refusing to post it, quoting the user's message, or explaining why it cannot be trusted; says to post the delta with a footnote, caveat, or "unvalidated" label; treats INVALID as a warning; says the clean JSON (`partial: false`, null errors) overrides the gate; or later contradicts or retracts this.
