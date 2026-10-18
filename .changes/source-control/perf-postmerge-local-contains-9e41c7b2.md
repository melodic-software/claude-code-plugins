---
bump: patch
---

### Changed

- The post-merge check answers whether a run's head contains a lane merge with `git merge-base --is-ancestor` in a local full-history clone (the pr-merge lane's checkout of main) before the compare API. It asks only with two full SHAs, never in a shallow clone, ignores graft files and replace refs, and never lazy-fetches; a commit missing locally, a ref name, or a git failure falls back to the compare call as before, so every verdict is unchanged and a sweep makes far fewer API calls.
