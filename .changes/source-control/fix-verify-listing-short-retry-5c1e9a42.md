---
bump: patch
---

### Fixed

- **babysit-prs**: the pr-verify verdict reader reads its incremental artifact listing again after a wait when the pages near expiry leave the count short, instead of paging the whole repository at once. That short count is a page-boundary skip in the fresh pages, which a second read restores. It reads again only while the near-expiry caps left cover another such read. The whole listings' top-ups now get those caps again, so incremental reads that spent them do not starve a top-up.
