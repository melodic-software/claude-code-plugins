---
bump: patch
---

### Fixed

- keep every docs fetch under the 30,000 characters of Bash output Claude Code reads back

  `docs-raw.sh` returns a section map for a page over 28,000 bytes and caps every body there, so
  the fetcher's output is never replaced by a saved-file stub.
