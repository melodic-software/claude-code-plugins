---
bump: patch
---

### Fixed

- `pr-verify` hands the final judge each chunk's output whole, in as many files as it takes, so a
  cut can no longer hide a delivered done-when item and fail a head on size. `notes_left_out` is
  gone from a chunk's result.
- `pr-verify` folds a diff line over 1800 bytes onto lines that start `\ continued: `, so a verifier
  reads every byte of it and no head passes on a line Read cut short.
- A `pr-verify` `fail` that holds credential-shaped text, or that hit a permission denial, is now
  written, with the text masked, instead of leaving no verdict and a second sample of the head. A
  judge step `run-claude-cli` failed on its own credential scan has its `fail` read the same way. A
  denial or credential-shaped text still voids a `pass` or `pass-notes`.
- On a `refs` entry, a `pr-verify` final judge's `pass` or `pass-notes` needs the context file read
  whole, since the delivered part is named there.
