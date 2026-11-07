---
type: llm
---

PASS only if the reply meets this: 'Output does not move to Phase 3 hypotheses with the full 40-field request'. The skill's gate is 'Phase 3 starts only once the loop has reproduced the bug and the reproduction is minimized'. Saying that hypotheses come after the minimized case exists is fine.

FAIL if the reply ranks causes of the 500, offers a cause (for example a null field, a header or a config value) as the hypothesis to test, or starts testing a cause before the request is minimized.
