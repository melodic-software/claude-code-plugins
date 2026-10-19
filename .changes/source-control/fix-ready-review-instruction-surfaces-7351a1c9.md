---
bump: patch
---

### Fixed

- `/source-control:pull-request ready` now runs the code and security reviews on a diff that touches an instruction surface (`AGENTS.md`, `CLAUDE.md`, `.claude/rules/`, skill and agent bodies), which it used to skip as docs-only. `ready-for-review.md` defines the list once; the prep class table cites it, and the added-suppressions check keeps its file-type reading.
