---
bump: patch
---

### Fixed

- `pr-verify` hands the final judge each chunk's output whole, in as many files as it takes, so a
  cut can no longer hide a delivered done-when item and fail a head on size. `notes_left_out` is
  gone from a chunk's result.
- `pr-verify` folds a diff line over 1800 bytes onto lines that start `\ continued:`, so a verifier
  reads every byte of it and no head passes on a line Read cut short.
- A `pr-verify` `fail` that hit a permission denial or holds credential-shaped text, a `pass` or
  `pass-notes` that holds a credential format, and any verdict from a judge step `run-claude-cli` failed
  on its own credential scan, is now written instead of leaving no verdict and a second sample of the
  head. A `pass` or `pass-notes` of that kind becomes a `fail` that counts toward the repeated-fail cap;
  one holding only a secret assignment, which may be a fixture, still leaves no verdict. Each publishes a fixed text and
  none of the model's, logs the credential's kind alone as a warning, and holds the pull request for a person with the
  human-gated label, a dequeue and a `security` stop reason, since a later clean commit rotates nothing. The verdict
  records `withheld: true` in code, so a fail quoting that text gets no hold and no model can claim one. The comment
  posts once per head and the label goes on in any pull request state, so a closed pull request that reopens stays
  held, whatever else the label stands for, and the comment keeps the label through
  `clear-escalations`, `enable-auto-merge`'s lift and `ci-status`'s cost-hold clear until a person removes it. A failed
  hold skips no notes, no fix round works past it, and a withheld fail stands on a short read with no
  notes or a scan stop that left no log. A denial alone still voids a `pass` or `pass-notes`. The scan
  reads through the
  `\ continued:` fold, with any white space before it, and across two quoted diff lines, and the prompts forbid quoting
  a credential.
- On a `refs` entry, a `pr-verify` final judge's `pass` or `pass-notes` needs the context read
  whole, in parts one Read returns, since the delivered part is named there. Chunk results over
  300000 bytes stop with no verdict before the final judge runs.
