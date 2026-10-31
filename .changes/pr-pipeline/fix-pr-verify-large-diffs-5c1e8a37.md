---
bump: patch
---

### Fixed

- `pr-verify` judges a diff of any realistic size. It splits a diff into as many chunks of at most
  300000 bytes as it takes, up to 12 (`MAX_CHUNKS` in `chunk-diff.sh`, which holds a 3 MB diff), each
  with its own judge step, and the head still passes only when every chunk and the final judge do. A
  file over 300000 bytes, or a diff that needs more than 12 chunks, still ends the run with no
  verdict and an error naming the file, or the diff's size and the chunk count.
