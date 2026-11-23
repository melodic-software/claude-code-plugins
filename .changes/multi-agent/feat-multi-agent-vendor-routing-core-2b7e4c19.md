---
bump: minor
---

### Added

- Trust-model vendor routing core for `/multi-agent:route vendors`: closed JSON Schemas (`benchmark-registry.schema.json`, `verdict-record.schema.json`), pointer-only `reference/benchmarks.json`, `fetch-boards` wrapper over `scripts/fetch-docs.sh`, Read-only `board-reader` agent, and `vendor-decide` script with command-line tests.
- Vendor routing eval cases `ro-vendor-cites-sources` and `ro-vendor-unread-page-abstains` on fixture pages, plus fixture-page staging for `ro-vendor-everyday-default` and `ro-vendor-heavy-above-default`.

### Changed

- `/multi-agent:route vendors` now fetches enabled registry pages through `fetch-boards`, dispatches `board-reader` per read page, decides via `vendor-decide`, cites every source with its read state, carries the untrusted-content framing inline, and names each tool's own skill for MCP-vs-CLI decisions.
- `reference/vendors.md` now states the trust model and points to `reference/benchmarks.json`, with the dated checked column and model names removed.
