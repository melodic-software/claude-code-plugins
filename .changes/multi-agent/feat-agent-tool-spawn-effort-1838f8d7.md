---
bump: patch
---

### Changed

- config reference: the `effort` values row now points at the model-config section listing which levels each model supports.
- defaults: the worker, verifier and retrieval roles now record the Agent tool's per-spawn effort docs as `pointer_spawn`, and their recheck triggers include a change to that parameter. Role values are unchanged.
