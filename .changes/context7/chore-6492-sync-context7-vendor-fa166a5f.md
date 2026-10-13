---
bump: patch
---

### Changed

- **`/context7:lookup` synced to upstash/context7 `522c4db`.** The vendored `find-docs` and `context7-cli` baselines are refreshed, and `metadata.upstream-version` now names that commit instead of `master`. The lookup workflow passes the user's language through `docs --language` when the installed CLI's `docs --help` lists it, and omits it on an older install, with a pointer record in place of a copy of the flag's behavior; it also gains the advice to describe what to look up rather than the task. The CLI reference is re-verified against `ctx7` 0.6.0. Upstream's switch to `npx ctx7@latest` for every call is not ported: this plugin keeps the global install its setup and context lines depend on, with `npx` as the documented fallback.
- **`update.sh` pins one upstream commit per run.** It resolves `upstash/context7` master once, fetches both baselines at that commit, and `--refresh-baseline` stamps that commit as `upstream-version` beside `synced`, so the baselines and the stamp always name the same revision.
