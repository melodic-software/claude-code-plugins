---
bump: patch
---

### Changed

- The read lane's `setup-env` copy takes the CI Node dependencies from `scripts/ci-deps/package.json` and `package-lock.json` instead of the synced `.github/standards/runner-policy` manifests.
