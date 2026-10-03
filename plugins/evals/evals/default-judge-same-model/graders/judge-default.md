---
type: llm
arm: both
---

PASS if the answer says the llm graders are judged by haiku (a small, fast model) by default, whatever `--model` is set to, so with `--model sonnet` and no `--judge-model` the judge is haiku.

FAIL if the answer says the judge follows or defaults to `--model` (so sonnet); names another default (opus, sonnet); says the judge is the same model as the one under test when no `--judge-model` is passed; names no judge model; or later contradicts or retracts this.
