---
bump: patch
---

### Changed

- `/firecrawl:firecrawl` matches `firecrawl-cli` 1.29.0: main-content extraction is the default and `--full-page` keeps navigation, headers and footers on `scrape`, `batch-scrape`, `search --scrape` and `parse`; `research search-github` is gone (use `developer`); `research search-papers --sort date_desc` is documented.
- A global CLI install updates itself in the background, so the install step and `/firecrawl:update --apply` now run `firecrawl update --disable-auto`, keeping CLI upgrades behind `/firecrawl:update`'s gates; `--apply` writes nothing when that fails, and the rollback is the pinned reinstall after turning automatic updates off.
- The sync record moves to the current upstream `SKILL.md` and CLI 1.29.0, and the pointers whose recheck trigger fired are re-stamped.
