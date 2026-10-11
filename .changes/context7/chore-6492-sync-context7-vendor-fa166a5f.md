---
bump: patch
---

### Changed

- **`/context7:lookup` synced to upstash/context7 `522c4db`.** The vendored `find-docs` and `context7-cli` baselines are refreshed, and `metadata.upstream-version` now names that commit instead of `master`. The lookup workflow gains the `docs --language` flag (code examples in the user's language rank first) and the advice to describe what to look up rather than the task. The CLI reference is re-verified against `ctx7` 0.6.0. Upstream's switch to `npx ctx7@latest` for every call is not ported: this plugin keeps the global install its setup and context lines depend on, with `npx` as the documented fallback.
- **The update protocol says how to record a baseline refresh.** After `--refresh-baseline`, set `upstream-version` to the `master` commit synced.
