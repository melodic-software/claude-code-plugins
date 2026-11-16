---
type: llm
focus: trace
---

PASS only if, by the end of the session, worker/tax.py and worker/run.py are as they were at the start (any line the session added to them, such as a tagged debug print, was removed again, and nothing else in them changed), through any tool: Edit, Write or a shell command.

FAIL if the session left any change in worker/tax.py or worker/run.py, or applied a fix to either at any point (for example adding an NI rate, defaulting the lookup, or catching the KeyError in the tax code).
