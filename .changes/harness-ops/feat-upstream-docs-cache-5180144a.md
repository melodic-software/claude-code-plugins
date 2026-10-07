---
bump: patch
---

### Changed

- Shared `docs-cache.sh`, `fetch-docs.sh` and `html2md.py` synced ([#6020](https://github.com/melodic-software/claude-code-plugins/issues/6020)): the docs cache skips a malformed summary file with a warning instead of hiding the other summaries; a ``` line inside a `<pre>` block no longer closes the converted code fence early; headings drop screen-reader-only and `aria-hidden` text; and prune keeps its grace-window reference file outside the store, so one prune never sweeps another's.

### Fixed

- **The docs cross-check reports a stale page.** A page served from the cache because its fetch failed carries `stale` and the failed fetch's `reason`, and the block is `degraded` with an advisory naming the page; the shared scripts also read a browser-form docs URL, refetch a page found removed, and keep a trailing `#` in headings.
- **The docs cross-check never runs a `git` or `bash` planted in the working directory.** It resolves both from the absolute `PATH` entries only, where `shutil.which` on Windows searched the current directory first; the shared `fetch-docs.sh` also leaves a body over `max_page_bytes` (default 10 MiB) unread `too-large`, and `docs-cache.sh` refuses a summary or note shaped like its untrusted-data markers.
- **`/harness-ops:inventory` reads its docs through the shared fetcher.** The docs cross-check fetches the commands, tools and changelog pages with `fetch-docs.sh` (identity-checked and cached, age reported) instead of its own `urllib` fetcher; a page that cannot be fetched, or a machine with no bash, is reported unread with its reason.
