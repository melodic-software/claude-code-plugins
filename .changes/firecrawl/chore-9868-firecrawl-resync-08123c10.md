---
bump: patch
---

### Changed

- `/firecrawl:firecrawl` matches `firecrawl-cli` 1.29.0: main-content extraction is the default and `--full-page` keeps navigation, headers and footers on `scrape`, `batch-scrape`, `search --scrape` and `parse`; `research search-github` is gone (use `developer`); `research search-papers --sort date_desc` is documented.
- A new gotcha says a global CLI install updates itself in the background and that CLI upgrades go through `/firecrawl:update`, not `firecrawl update`; `/firecrawl:update`'s rollback step turns automatic updates off first.
- The sync record moves to the current upstream `SKILL.md` and CLI 1.29.0, and the pointers whose recheck trigger fired are re-stamped.
