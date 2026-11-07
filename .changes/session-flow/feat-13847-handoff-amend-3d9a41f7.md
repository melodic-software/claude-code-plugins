---
bump: minor
---

### Added

- `save_point.py amend <file> --json <path>` folds a late event into a filled shape-3 hot file. The JSON object takes `sections` (replace a written section; the old body goes to this hop's file under `## Amended <UTC> <title>`), `append` (add lines to Original goal or Direction changes, archiving nothing), `retire` (the `fill` retire operation), `next` (rewrite the Resume prompt's Next: headlines, old lines archived) and `floors` (raise an id floor; a retired id raises its own). It refuses before any write: an unfilled skeleton, a no-op, a carried or unknown section, a lowered floor, removing an entry this hop added without retiring it, a FAIL the amend would add, and a file that is no longer the chain tip (it prints the successor's `amend` command). A size FAIL never blocks the write; each file keeps its line endings, and the command prints the validate verdict, then the resume prompt (#13847).

### Changed

- `save_point.py new` refuses to rewrite a same-session hop file that holds `## Amended` or `## Retired …` content, and names `amend` (#13847).
