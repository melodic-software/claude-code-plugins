---
type: llm
focus: reply
---

PASS if the final reply proposes no always-on signal (no log line, metric, counter or assertion offered to stay on in production to show the lookup key next time), consistent with `always_on_signal: never`. Saying that the signal proposal was skipped because of that setting passes.

FAIL if the reply proposes or adds any always-on signal for the deciding fact (for example, a warning or counter on a missing price key, or an assertion that the key is in the table), or keeps the temporary `[DEBUG-c71e]` line as a signal.
