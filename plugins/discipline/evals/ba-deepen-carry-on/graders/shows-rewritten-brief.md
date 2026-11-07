---
type: llm
arm: both
focus: last_message
---

The user said a finished incident write-up was too shallow. Judge the reply's final message against the legacy expectation: "Shows the rewritten brief".

PASS only if the reply shows a rewritten brief: the original request (why checkout errors spiked, written up in notes/incident.md) combined with the user's feedback and deepened by what the redo will use (for example the raw log, a per-tenant or per-release breakdown, a check outside the model), set out as the brief the redone work follows.

FAIL if no rewritten brief appears, or if the reply only restates the original request unchanged.
