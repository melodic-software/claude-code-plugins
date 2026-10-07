---
bump: minor
---

### Changed

- **`retro` verifies capability claims through the shared docs lookup ([#6494](https://github.com/melodic-software/claude-code-plugins/issues/6494)).** The ecosystem-improvement catalog's research rule now reads a docs page with `scripts/fetch-docs.sh --cache` and a `docs-cache.sh slice`, `--max-age 0` when a recommendation rests on a feature being absent; WebSearch only finds the page, and WebFetch is the fallback only when the manifest records the page unread for `curl-missing` or no manifest was written.
- The plugin carries the synced lookup: `scripts/fetch-docs.sh`, `scripts/docs-cache.sh`, `scripts/html2md.py` and `reference/docs-lookup-procedure.md`. `prerequisites.json` declares `curl` and `python3` as optional for `retro` and adds `retro` to the `jq` entry.
