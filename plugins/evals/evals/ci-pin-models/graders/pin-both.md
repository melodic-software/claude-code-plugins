---
type: llm
arm: both
---

PASS if the CI command pins both the model under test (`--model`) and the judge (`--judge-model`) with full model IDs (for example `claude-sonnet-5`), or the answer tells the user to pin both by full model ID, so a model rollout is not read as a plugin regression. Full IDs held in workflow variables count.

FAIL if only one of the two models is pinned; either pin is an alias such as `sonnet`, `haiku` or `opus`, or the answer says an alias is enough to pin; the answer recommends tracking the latest model; or it later contradicts or retracts this.
