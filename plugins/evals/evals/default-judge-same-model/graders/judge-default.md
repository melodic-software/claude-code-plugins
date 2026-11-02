---
type: llm
arm: both
---

PASS if the answer says the judge is not set by `--model`: it is whatever `--judge-model` resolves to, which has its own default, so passing only `--model sonnet` does not make sonnet the judge. The answer either names that default (haiku, or a small, fast model) or says where to read the current one: the `--judge-model` row of the plugin-evals command options table, or `claude plugin eval --help`.

FAIL if the answer says the judge follows or defaults to `--model` (so sonnet); names sonnet or opus as the default judge; says the judge is the same model as the one under test when no `--judge-model` is passed; neither names a default nor says where to read it; or later contradicts or retracts this.
