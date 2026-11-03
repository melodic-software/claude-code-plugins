---
bump: minor
---

### Added

- `batch-scrape` in `/firecrawl:firecrawl`, for many known URLs as one job

### Changed

- sync the wrapper skill with upstream and `firecrawl-cli` 1.26.24

  `search-feedback` documents `--valuable-results` for returned results and
  narrows `--valuable-sources` to URLs the search did not return. `crawl`
  documents blocking on a job id and writes `--status` output to disk now that
  it reads the pages. The wrapper no longer says the CLI reads exactly three
  env vars. `/firecrawl:update` records the new upstream hash and CLI version.
