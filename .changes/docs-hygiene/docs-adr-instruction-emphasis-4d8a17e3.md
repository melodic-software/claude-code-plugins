---
bump: patch
---

### Changed

- `write-for-agents` states each rule in plain words with its scope and reason, with no all-caps and no `IMPORTANT`, `MUST`, `NEVER`, `ALWAYS` or `CRITICAL` markers; a plain firm word stays when the sentence gives scope and reason. A rule that must hold every time goes to a hook, deny rule or CI check, and bold is structure only: a list-item label or a defined term at first use. Recorded in ADR 0098.
