---
bump: minor
---

### Changed

- `address-feedback` may fix a finding in any file the pull request already changes, rename sources included, not only in the thread's own scope. The select job writes those files as `pr_paths` in the thread file and `run.json`, less `.github/workflows/`, `.gitmodules`, `CODEOWNERS`, `settings*.json`, package manifests, `requirements*.txt` and the HIGH floor's trusted-actor list, trusted-trigger check and `resolve-config`. `apply-patch.mjs`'s `kept-threads` rule and the reply job admit them, and only as changes to an existing file: a file the fix creates keeps the old scope. A `VALID` fix commit lands when it changes the thread's path or any `pr_paths` file. Every apply-patch refusal still applies.
