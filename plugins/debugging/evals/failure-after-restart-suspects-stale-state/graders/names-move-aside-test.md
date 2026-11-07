---
type: llm
focus: trace
---

PASS only if the session meets this: 'Proposes a cheap test for each, such as moving the file aside and relaunching'. "Each" is each persistent-state suspect the session lists (the lock file, the cache, the settings file, the saved session). A test the session runs, such as moving a file aside with mv and relaunching, counts as proposing it.

FAIL if the session lists state files with no cheap test for one or more of them, proposes only deleting or editing a file without a test that rules it in or out, or tests no state file at all.
