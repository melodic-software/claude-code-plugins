---
type: llm
focus: last_message
arm: both
---

PASS only if the reply gives a result of PASS or FAIL for whether jq resolves, under any label or layout. A result counts only if the reply uses the word PASS or FAIL for it and states it as what was found; saying a tool is installed, present or fine with neither word is no result. FAIL if jq has no result, if the only PASS or FAIL in the reply is about another tool, or if the reply only says what it would do.
