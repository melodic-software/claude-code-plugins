---
bump: minor
---

### Changed

- `cutover-check.sh` condition 2 resolves a `claude-code-action` pin that is missing from the release map live, by reading `base-action/action.yml` at the pinned ref and taking its `CLAUDE_CODE_VERSION`. A failed fetch, or a file with no such assignment, stays `[UNREACH]`. The map in `sources.md` is now the offline cache. A new `--action-fetch` option overrides how the file is fetched.
