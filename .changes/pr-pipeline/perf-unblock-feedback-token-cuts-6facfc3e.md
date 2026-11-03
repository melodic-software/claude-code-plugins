---
bump: patch
---

### Changed

- The pr-unblock dispatcher (`pr-unblock-dispatch.yml`) lists open pull requests once a run instead of three times: resolve-conflicts, review-dependency, fix-ci and fix-docs read the same GraphQL listing page by page, each page sent once, which carries every field each of them read before. A run with 50 or fewer open pull requests makes one listing request where it made three. fix-ci and fix-docs now judge check rollups read at the start of the run, before resolve-conflicts waits on pull requests whose mergeable state is still unknown.
