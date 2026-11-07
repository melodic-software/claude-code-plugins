---
type: llm
---

PASS only if the reply's hypotheses rank persistent state left by the run before the reboot (the lock file, the cache, the settings or config file, the saved session) first, above any code hypothesis, and give each of those a cheap test such as moving the file aside and relaunching. Reporting which one turned out to be the cause, after testing them, still passes.

FAIL if the reply opens with or ranks first a code defect (a bug in sync_client.py, a dependency or a version change) although no code changed, lists the state files without a test for each, or names a cause without having ranked the state files.
