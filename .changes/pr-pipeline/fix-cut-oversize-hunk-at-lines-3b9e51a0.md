---
bump: patch
---

### Fixed

- pr-verify and pr-review-main judge a pull request whose file holds one hunk over one chunk (300000 bytes) instead of giving no verdict. `diff_chunking.py split --cut-lines` cuts such a hunk between its lines, each cut under an `@@` header recounted for the lines it holds, and the chunk prompts and the final judge say a piece can hold part of a hunk. Without `--cut-lines` the splitter still refuses such a hunk, so ci-workflows' `generate-review-chunks` keeps its partial review. Only a single line over a chunk, or a diff over `MAX_CHUNKS` chunks, still gets no verdict.
