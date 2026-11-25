---
bump: patch
---

### Fixed

- The merge-risk rating (`pr-rate-merge-risk.yml`) no longer refuses a diff over 600,000 bytes. `input.mjs` cuts the diff with `diff_chunking.py` into chunks of at most 300,000 bytes and parts one Read returns whole; the rating's agents read every chunk at once (`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS` raised to a rater and a checker per chunk), so wall time stays one chunk's read. Up to 50 chunks (15 MB) are rated; chunks past that are left out and counted. `write-rating.mjs` checks the execution file for a whole, successful Read of every part and adds a HIGH `Diff coverage` row, which demotes the head, for any part unread or chunk left out. The rating's output (`rating.json`) is unchanged.
