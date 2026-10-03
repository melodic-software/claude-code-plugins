---
type: llm
arm: both
---

PASS if the answer proposes measuring the rules by removing them during real work and watching what goes wrong: it names `/harness-config:unhobble`, or it describes that experiment (strip or remove the instructions, for example on a branch; work normally; log where the model stumbles; restore only what repeated evidence earns).

This grades this repository's preferred route. A headless A/B (running the same prompts with and without the instruction files and comparing outputs) without logging stumbles during real work does not meet it.

FAIL if the answer proposes only a plugin eval, a shim plugin that re-injects the rules, a headless A/B comparison, hooks or linters, or no alternative; or if it later contradicts or retracts this.
