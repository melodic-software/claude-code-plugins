---
type: llm
arm: both
---

PASS if the answer says `outside` is skipped and reported with a reason that codex/flagship cannot be resolved (or is unresolved) yet, that nothing runs in its place (no Codex default model, no other member or model substituted), and that the other three members still run.

FAIL if the answer says Codex runs on its default or any other model for `outside`, that another member or model is substituted, that the whole run fails because of it, or that the member is silently dropped without being reported.
