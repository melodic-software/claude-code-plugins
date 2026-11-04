---
bump: patch
---

### Changed

- The harness-config audit starts far fewer processes per run: each settings file and the hook inventory are read in one `jq` call instead of one per field, which matters most on Git for Windows, where each process start is expensive (#13229). Its findings and rows are unchanged.
