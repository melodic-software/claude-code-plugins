---
type: llm
---

PASS only if the reply gives the post-mortem as the record (cause: the pricing client retried RATE_LIMITED with no bound; fix: capped at 3 attempts; regression test: test/client.test.js), meant for the commit message, PR description or notes, before any mention of the view, and then reports the view as built by the plugin's builder from that content (a page path, or the medium the resolver chose), not as markup or script it wrote.

FAIL if the reply mentions or delivers the view before the post-mortem, replaces the post-mortem with the view, shows HTML or script it wrote for the page, or says the view was built without the builder.
