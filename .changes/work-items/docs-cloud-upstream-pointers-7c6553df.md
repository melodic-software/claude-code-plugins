---
bump: patch
---

### Fixed

- Tracker contract: "Degradation without `gh`" no longer names cloud sessions as a no-`gh` environment. It points at the upstream installed-tools and GitHub-proxy sections, and notes that GraphQL-backed `gh` calls fail there even with `gh` present.
