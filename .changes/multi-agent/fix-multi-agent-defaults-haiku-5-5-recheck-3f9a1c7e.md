---
bump: patch
---

### Fixed

- **`/multi-agent:audit-defaults` no longer tells the caller to pass `defaults` to `list-pointers.sh`.** The script reads that word as an owner and exits 2. Step 3 now says to pass only a role or `fanout`, or nothing.
- **The `fanout` and `worker` defaults are rechecked as of 2026-10-10.** The cost page still recommends Opus 5.5 at medium effort, so no model or effort value changes. The two recheck triggers now say "a new model named on the cost page", because that page has no model table.
