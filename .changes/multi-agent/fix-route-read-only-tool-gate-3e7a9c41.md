---
bump: patch
---

### Fixed

- `vendor-decide` takes `--use <investigate|task>` (default `task`). With `investigate`, the
  `--needs-tools` gate checks the vendor's `read_only_tools` from `external-agents models`,
  falling back to `tools` when the entry has none, so a read-only brief no longer routes to a
  vendor whose read-only mode refuses a tool it needs. The route skill passes the brief's use, and
  a research or fact-check brief names `web` in `--needs-tools`.
