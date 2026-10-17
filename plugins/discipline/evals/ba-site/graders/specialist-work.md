---
type: llm
arm: both
focus: last_message
---

The user made a request. Judge the reply's final message.

PASS only if both hold: the reply draws on at least one field beyond the request's obvious one (for example game design, typography, accessibility, statistics or operations brought to a request that is not about them), and wherever it brings in an expert it asks for that expert's actual work (what they would do, check or produce), not for a persona to act out.

FAIL if the reply stays inside the request's own field, or if it asks the model or an agent to "act as", "pretend to be" or "you are" an expert without naming the work that expert would do.
