---
bump: patch
---

### Fixed

- The pr-merge lane sorts a Dependabot pull request that carries a lanes App `[dependabot skip]` commit to tier `review`, so it merges on the App's `verdict=merge` marker at the current head instead of being refused for the App's own commit.
