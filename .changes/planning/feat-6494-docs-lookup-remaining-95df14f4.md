---
bump: minor
---

### Changed

- **`draft-goal-condition` reads the `/goal` page through the shared docs lookup ([#6494](https://github.com/melodic-software/claude-code-plugins/issues/6494)).** Step 1 runs `scripts/fetch-docs.sh --cache --max-age 0` and slices the sections it needs with `docs-cache.sh`, so the condition shape and the character limit come from fresh, whole bytes; WebFetch is the fallback only when the manifest records the page unread for `curl-missing` or no manifest was written.
- The plugin carries the synced lookup: `scripts/fetch-docs.sh`, `scripts/docs-cache.sh`, `scripts/html2md.py` and `reference/docs-lookup-procedure.md`. `prerequisites.json` adds `draft-goal-condition` to the optional `curl`, `jq` and `python3` entries.
