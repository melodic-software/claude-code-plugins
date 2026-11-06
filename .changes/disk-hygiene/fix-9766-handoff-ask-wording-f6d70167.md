---
bump: patch
---

### Fixed

- The Windows `handoff-apply` hook ask now says to confirm the tier and paths "the report just showed", since the Windows lane runs no preview. The Windows lane shows the tier's paths as a list and asks no separate approval question, because the hook ask is the approval. A new eval case, `cl-windows-handoff-no-separate-approval`, covers that lane (#9766).
