---
bump: minor
---

### Added

- The pr-merge verdict reader has an index mode: once `verify-legacy-fails.json` sits beside it, a judgment finds every FAIL by exact-name reads of the FAIL index (`pr-verify-index-pr-<n>`, `-sha-<head>`, `-ref-<digest>`, `-issue-<i>`) and the runs they name, instead of paging the whole artifact listing. Any read that fails or misses its own count refuses. `babysit_verify_evidence.py legacy-fails` builds that file from a listing that holds GitHub's live count.
