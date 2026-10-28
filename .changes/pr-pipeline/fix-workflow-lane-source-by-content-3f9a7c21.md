---
bump: patch
---

### Changed

- The hold-path floor documentation states which workflow files are lane sources: a changed workflow whose head copy cannot post as `github-actions[bot]` with a write token nor reach a secret no longer stops the security review from binding, while the review callers, `pr-merge.yml` and `pr-require-checks.yml` still do (owner direction 2026-10-27).
