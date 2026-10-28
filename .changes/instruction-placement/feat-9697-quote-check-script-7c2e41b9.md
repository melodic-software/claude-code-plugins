---
bump: minor
---

### Added

- **`scripts/quote-check.sh` checks each mechanics quote against its docs section** ([#9697](https://github.com/melodic-software/claude-code-plugins/issues/9697)). It reads only `context/mechanics-sources.tsv` and takes no arguments. Each page is fetched once through `scripts/fetch-docs.sh --cache`, and the section the URL's anchor names is taken with `scripts/docs-cache.sh slice`. It prints one line per record: `verified <id>`; `drift <id> <url>`, followed by the stored quote and the section's closest sentence; or `unverified <id> as of <as_of>` when the page could not be read fresh. It exits 0 whatever the results are. `QUOTE_CHECK_FIXTURE_DIR` points it at local page snapshots, so `scripts/quote-check.test.sh` covers the verified, drift and unverified cases without touching the network.
