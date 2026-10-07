---
bump: patch
---

### Changed

- **`migrate`'s cutover check reads the env-vars page through the plugin's docs fetcher ([#6494](https://github.com/melodic-software/claude-code-plugins/issues/6494)).** `cutover-check.sh` runs `scripts/fetch-docs.sh --cache --max-age 0` instead of `curl`, so the page is slug-checked against the docs index, fresh, and never a partial body; an unread page names the manifest's reason. The test suite isolates the docs cache and covers a fetched page and an unread one.
