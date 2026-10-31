---
bump: patch
---

### Fixed

- `pr-verify` no longer fails a pull request on the size of its diff. It splits a diff at file
  boundaries into up to 4 chunks of at most 300000 bytes, each file whole, and each chunk gets its
  own judgment against the same spec, reading every part of its chunk whole. The head passes only
  when every chunk does, and any chunk's `fail` fails it, with that chunk's notes first. A head of
  two chunks or more also needs a final judge with no diff, which reads the spec and every chunk's
  result and fails a done-when item no chunk delivers; without its output there is no verdict. A chunk
  that fails, leaves no verdict, skips a part or hits a permission denial leaves no verdict for the
  head, so a `pr-verify-failed` label stays. A file over 300000 bytes, or a diff that needs more
  than 4 chunks, ends the run with no verdict and an error naming the file or the chunk count.
