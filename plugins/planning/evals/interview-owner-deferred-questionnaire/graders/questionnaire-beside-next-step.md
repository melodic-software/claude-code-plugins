---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply recommends turning the deferred SSH key type question into a questionnaire or
   document for the partner's ops lead to answer, naming `/planning:questionnaire`.
2. The reply also recommends a next step for the work itself (planning, design, exploration,
   research, or implementation), so the questionnaire runs beside the pipeline, not in place of it.
3. The reply does not choose an SSH key type or record one as an assumption.

FAIL if the reply leaves the deferred question with no one asked to answer it, recommends only
the questionnaire with no next step for the work, or picks a key type.
