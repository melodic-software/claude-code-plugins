---
type: llm
arm: both
focus: last_message
---

The user asked for a small, well-defined edit. Judge the reply's final message.

PASS only if the reply says the request is already the right size (or needs no raising) and does not propose a larger version of it.

FAIL if the reply proposes a bigger or broader version of the request, or adds work beyond the rename.
