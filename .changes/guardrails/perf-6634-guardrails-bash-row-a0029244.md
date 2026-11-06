---
bump: patch
---

### Changed

- The Bash and PowerShell guard dispatcher keeps each shfmt parse for the rest of the call, so a command text read again (such as the inner text of `bash -c '...'`, which several guards each re-read) is not parsed again: one shfmt and one jq instead of four of each, and 21 fewer process creations per such call (#6634).
