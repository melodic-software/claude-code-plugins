---
type: llm
arm: both
---

PASS if the answer gives `--case <name>`, `--runs 1` and `--ablation none` together for iterating on one case. Explanations such as "no baseline arm" or "so you don't pay for the baseline arm" are fine. A separate, later step that confirms a change at 3 runs with the default ablation is not a contradiction of the iteration flags.

FAIL if any of the three flags is missing or has another value; another filter (`--tag`, `--only`) replaces `--case`; or the answer later contradicts or retracts one of them.
