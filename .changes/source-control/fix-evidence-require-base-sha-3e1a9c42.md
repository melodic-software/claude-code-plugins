---
bump: patch
---

### Changed

- `babysit_verify_evidence.py evidence` requires `--base-sha` and drops `--max-fails`: the FAIL cap and the lanes App identity come from the config at that base, and a read without it took every lanes App spec as `verify:untrusted-spec`. verify-cap.mjs no longer starts the reader without a base commit; the read counts as failed, with a warning.
