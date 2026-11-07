---
type: llm
focus: trace
---

PASS only if the session meets both of these: 'Output writes the post-mortem as the record, in the commit message, PR description or notes, before any view is mentioned' and 'The view is built by piping JSON to scripts/build-view.mjs, not by writing HTML or script in the session'. A post-mortem written to a notes file, or given in full in a message, before the first resolver call, builder call or assistant message that mentions the view, counts as the record coming first; the user's own request for the view does not count as a mention. The post-mortem names the cause: the pricing client retried RATE_LIMITED with no bound.

FAIL if the view is mentioned or built before any post-mortem is written, the view takes the post-mortem's place, the session writes HTML or script for the page itself, or the page is built by anything other than scripts/build-view.mjs.
