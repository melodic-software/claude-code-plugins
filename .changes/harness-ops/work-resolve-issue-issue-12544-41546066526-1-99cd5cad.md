---
bump: patch
---

### Changed

- `/harness-ops:plugins sync` skips Step 1's `claude plugin marketplace update` for a `github` or `git` marketplace when `git ls-remote` shows the source's ref already at the clone's HEAD, since the CLI re-clones the marketplace on every refresh. The skip needs a clone at `installLocation` with no modified or untracked file, whose `origin` is the recorded source, and a pinned `ref` checked out as that branch; any other case, an unreachable remote included, runs the refresh. The digest records a skip as `refresh.skipped` (`{head, ref}`), and the report adds a `refresh skipped` row (#12544).
