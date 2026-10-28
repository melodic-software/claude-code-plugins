---
bump: patch
---

### Fixed

- `/harness-ops:plugins sync` no longer drops a marketplace from the digest on a large fleet. `sync-run.sh` used to pass the block's fields, the divergence records and installed rows among them, to jq as command-line arguments, and on a fleet with about a thousand install records one of them grew past the kernel's per-argument limit, so the exec failed. The block's JSON fields now go to jq through a file in the run directory, and the digest reads the blocks with `--slurpfile`. The divergence split, the first-pass sidecar, the cache-check fallback and the disabled-install list read their fleet-sized inputs the same way.
- A marketplace block that cannot be assembled is no longer left out silently. The run adds an `errors[]` entry naming the marketplace and the jq failure, and the report lists it under `Action needed`, so the report no longer reads as if no marketplace resolved.
