---
bump: patch
---

### Fixed

- `fetch-docs.sh` follows a redirect from `claude.com` to `claude.dev` on the same path, so a `claude.com` blog page reads; every other cross-host redirect still leaves the page unread.
