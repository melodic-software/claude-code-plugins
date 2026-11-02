---
bump: minor
---

### Added

- The pr-merge verdict reader has an index mode: once `verify-legacy-fails.json` sits beside it, a judgment finds every FAIL by exact-name reads of the FAIL index (`pr-verify-index-pr-<n>`, `-sha-<head>`, `-ref-<digest>`, `-issue-<i>`) and the runs they name, instead of paging the whole artifact listing. Any read that fails or misses its own count refuses.
- `babysit_verify_evidence.py legacy-fails --merge-sha <sha>` builds that file. It reads every pr-verify run in one-day `created` windows up to the cutover the merge commit sets, and each run's artifacts, each read holding its own `total_count`. It then adds every run a whole artifact listing names, and refuses when a listed FAIL is still missing. Its calls are paced, capped per rate-limit window and resumable from a checkpoint.
