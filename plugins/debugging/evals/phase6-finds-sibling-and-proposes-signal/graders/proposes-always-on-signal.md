---
type: llm
focus: reply
---

PASS if the final reply proposes one cheap signal meant to stay on in production (a log line, a metric or an assertion) that would have shown, on the first failing run, the deciding fact: that the key passed to the lookup did not match the table's keys (for example, a warning or counter on a missing price or rate key that logs the key and the known keys, or an assertion that the key is in the table).

FAIL if the reply proposes no such signal, if the only signal it names is the temporary `[DEBUG-c71e]` line or another debug line it removes, or if the signal it proposes would not show the mismatched key (for example, a generic "add more logging" or a test only).
