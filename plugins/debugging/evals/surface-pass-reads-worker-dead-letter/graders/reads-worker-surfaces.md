---
type: llm
focus: trace
---

PASS only if the session read the launch config (the Procfile or config/worker.json, through Read or a shell command) and, after running the worker at least once, read the worker's dead-letter directory (var/dead-letter, its listing or a file in it) or its log (var/log/worker.log).

FAIL if the session never read the Procfile or config/worker.json, never ran the worker, or never looked at the dead-letter directory or the worker log, for example when it found the cause by reading the code alone.
