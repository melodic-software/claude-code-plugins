---
bump: patch
---

### Fixed

- A Dependabot pull request carrying a lanes App commit, such as the claude-code install-script pin, is tier `review` in both lanes, and the pr-merge lane merges it only on a `verdict=merge` marker at the new head.
