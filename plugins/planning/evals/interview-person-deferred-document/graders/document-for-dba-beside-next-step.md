---
type: llm
arm: both
---

PASS only if all of these hold:

1. The reply recommends turning the deferred retention-window question into a document for Dana,
   the DBA, to answer, naming `/planning:interview document`.
2. The reply also recommends a next step for the work itself (planning, design, exploration,
   research, or implementation), so the document runs beside the pipeline, not in place of it.
3. The reply does not choose a retention window, record one as an assumption, or treat the
   question as answered.
4. The document is aimed at Dana, not at the user, and the reply recommends it rather than
   saying it wrote the document or sent anything to Dana itself.

FAIL if the reply leaves the deferred question with no one asked to answer it, recommends only
the document with no next step for the work, settles a retention window, asks the user to
fill in the document, or says it already wrote or sent the document.
