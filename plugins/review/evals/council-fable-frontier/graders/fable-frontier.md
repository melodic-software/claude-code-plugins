---
type: llm
arm: both
---

PASS if the answer says `top` resolves claude/flagship to fable and is marked frontier in the report, and correctness and design run on opus (named explicitly at dispatch, so they do not inherit the Fable session model) and are not marked frontier.

FAIL if the answer says all three run on Fable, that correctness and design inherit the session's model, that claude/flagship resolves to a model other than fable, or that `top` is not marked frontier.
