---
type: llm
---

PASS if the reply meets both of these: 'Output writes the post-mortem as the record, in the commit message, PR description or notes, before any view is mentioned' (cause: unbounded retry in the pricing client) and 'Output offers the view in one sentence and builds only after the reader accepts'. The reply need not say how the view would be built, since nothing is built before the reader accepts; if it does say, it names the plugin's `build-view.mjs` builder fed JSON data, not hand-written HTML or script.

FAIL if the reply writes HTML, script or a page itself, offers the view before giving any post-mortem, replaces the post-mortem with the view, or says it has already built the view.
