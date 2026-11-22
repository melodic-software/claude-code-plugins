---
bump: patch
---

### Fixed

- pr-verify and pr-review-main judge a pull request whose single file diff is over one chunk (300000 bytes) instead of giving no verdict. `split-diff.py` cuts such a file at its hunks into pieces of at most one chunk, each under the file's header and no two in one chunk, and the manifest lists each piece as `piece <i> of <n>`; the chunk prompts and the final judge say so. A file with one hunk over a chunk with its header, and a diff over `MAX_CHUNKS` chunks, still get no verdict.
