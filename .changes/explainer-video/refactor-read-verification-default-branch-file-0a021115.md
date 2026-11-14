---
bump: patch
---

### Changed

- The verification level reader now reads the team file through `lib/default-branch-file.sh`; levels and messages are unchanged.
- `lib/default-branch-file.sh` reads the last fetched copy of the default branch when the fetch fails, and says it may be stale, instead of exiting 2; the stills settings still never come from the working tree.
