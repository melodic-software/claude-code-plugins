---
type: llm
focus: trace
---

PASS only if the session launched the client (python3 sync_client.py, or a script or test that runs it and checks for the error) and saw it fail before it moved, renamed, deleted or edited any file under state/ to test a hypothesis.

FAIL if a file under state/ was moved, renamed, deleted or edited before the client was first launched, or if the client was never launched.
