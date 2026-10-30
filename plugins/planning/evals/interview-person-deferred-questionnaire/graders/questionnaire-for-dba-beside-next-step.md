---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply recommends turning the deferred retention-window question into a questionnaire or
   document for Dana, the DBA, to answer, naming `/planning:questionnaire`.
2. The reply also recommends a next step for the work itself (planning, design, exploration,
   research, or implementation), so the questionnaire runs beside the pipeline, not in place of it.
3. The reply does not choose a retention window, record one as an assumption, or treat the
   question as answered.
4. The questionnaire is aimed at Dana, not at the user, and the reply recommends it rather than
   saying it ran the questionnaire or sent anything to Dana itself.

FAIL if the reply leaves the deferred question with no one asked to answer it, recommends only
the questionnaire with no next step for the work, settles a retention window, asks the user to
fill in the questionnaire, or says it already ran or sent the questionnaire.
