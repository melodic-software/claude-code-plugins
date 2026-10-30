---
bump: patch
---

### Fixed

- `collect-patch.sh` writes an exact rename (100% similarity) as a rename header, so a moved file
  no longer counts its whole content twice against the 256 KiB patch cap; a rename with edits is
  still a deletion and an addition. `apply-patch.mjs` already checks the tree the patch builds with
  rename detection off, so a rename's old and new path each meet every refusal, the path
  predicates, `max-files` and the blob size and credential checks.
