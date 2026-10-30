---
bump: minor
---

### Changed

- pr-review-main reviews a diff over its 300000-byte cap in chunks instead of stopping. The diff
  splits into at most 4 chunks of at most 300000 bytes, cut at file boundaries with each file
  whole, and each chunk is reviewed by its own run. The lane's one verdict sums the chunks'
  findings, takes the most CRITICAL ones any one chunk found, and binds as a single-pass verdict
  does. A `pr-review-main chunks` notice gives the chunk count and each chunk's bytes, and a
  `pr-review-main chunk` notice per chunk its bytes, findings and CRITICAL ones. A diff that holds
  a single file over 300000 bytes, or needs more than 4 chunks, still stops as `too-large`. A
  chunk that fails, leaves no result or skips a part writes no verdict: the record job posts
  `verdict=none reason=chunk-failed` on the head and the leg fails.
