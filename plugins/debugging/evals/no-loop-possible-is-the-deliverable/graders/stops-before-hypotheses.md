---
type: llm
---

PASS if the reply says explicitly that a reproduction loop cannot be built with what is available, lists the loop-building strategies it considered, asks for at least one of: access to an environment that shows the lag, a captured artifact (HAR file, log dump, recording with timestamps), or permission to add temporary production instrumentation, and stops there.

FAIL if the reply goes on to rank or test likely causes of the lag (for example "it's probably the main thread blocking on JSON parsing") as though a loop existed, or proposes a fix.
