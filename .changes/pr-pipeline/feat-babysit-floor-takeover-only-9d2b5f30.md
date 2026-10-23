---
bump: patch
---

### Changed

- The pr-merge HIGH path floor holds only the takeover set: the trusted-actor list, the trusted-trigger check, `CODEOWNERS`, `.gitmodules` and `resolve-config`. Agent permission config, package manifests and lockfiles, and the release and `id-token: write` workflows merge on the review lanes. The `high-path-floor` schema description and the README say so.
