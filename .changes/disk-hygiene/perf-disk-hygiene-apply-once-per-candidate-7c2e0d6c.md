---
bump: patch
---

### Fixed

- `hygiene.py apply` and `handoff-apply` probe open handles with one `lsof` run per approved candidate, read the mount table once per candidate and recheck tracked VCS state once per candidate just before its removal, instead of repeating each per captured entry. An entry lsof names, or a directory holding one, is skipped as `locked` while its siblings are removed; an lsof diagnostic or timeout still skips every entry as `handle-state-unverified`, an open name that maps to no snapshot entry holds the whole candidate, and a tracked or unverifiable recheck skips every entry of the candidate.
- The handle probe reads an open file from lsof's named output whether lsof exits 0 or 1, since `lsof +D` exits 1 while listing a held file; exit 1 with no output and no diagnostics is still the only clear result.
- `hygiene.py apply` reuses its approval-token preview instead of previewing twice, so one candidate costs two `lsof` runs in total, and resolves each removed entry's parent once per candidate.
