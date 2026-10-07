---
bump: minor
---

### Changed

- **The changelog and upstream-claim reads go through the docs cache** ([#6484](https://github.com/melodic-software/claude-code-plugins/issues/6484)). `changelog-status.sh` and the changelog fetch route call `fetch-docs.sh --cache --max-age 0`, so the range is computed from fresh bytes and a failed fetch is unread, never a stale cached copy. `/harness-ops:inventory` and `/harness-ops:audit-native-overlap` verify an upstream claim with `fetch-docs.sh --cache` in place of a raw `curl`, search the page file locally, and report the page's age from the manifest; the fetcher checks the slug against the docs index.
- **`curl` and `python3` are declared prerequisites** of the changelog, inventory and audit-native-overlap skills: `curl` required for the docs fetch, `python3` optional for converting a page served only as HTML.
