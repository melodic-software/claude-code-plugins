---
bump: minor
---

### Changed

- **`fable-5` reads a chapter's Pointer through the shared docs lookup ([#6494](https://github.com/melodic-software/claude-code-plugins/issues/6494)).** Chapter routing now says to read a pointed vendor docs section with `scripts/fetch-docs.sh --cache` and the section's `docs-cache.sh slice`, with WebFetch only when the manifest records the page unread for `curl-missing` or no manifest was written. The Opus 5.5 chapter's unattended-run Pointer names the same route.
- The plugin carries the synced lookup: `scripts/fetch-docs.sh`, `scripts/docs-cache.sh`, `scripts/html2md.py` and `reference/docs-lookup-procedure.md`. `prerequisites.json` adds `fable-5` to the optional `curl` and `jq` entries and declares `python3` as optional.
