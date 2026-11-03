---
bump: patch
---

### Changed

- **`/context7:lookup` synced to upstash/context7 `ceaf5f9`.** The vendored `context7-cli` baseline is refreshed, and `metadata.upstream-version` names that commit. Its new `ctx7 search` command is not ported: the current `ctx7` release does not have it, so the CLI reference records that with a recheck trigger, and lookups stay `ctx7 library`, then `ctx7 docs`.
