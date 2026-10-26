---
bump: patch
---

### Fixed

- pr-merge keeps the verifier's carried reads when the merge job's `pr-merge-run-cache` file does not read. `carry-run-cache.mjs read` now warns and treats that file as absent instead of dropping `pr-merge-verify-run-cache` with it; a failed trust check still carries nothing. The run cache section names both artifacts and what each carries.
