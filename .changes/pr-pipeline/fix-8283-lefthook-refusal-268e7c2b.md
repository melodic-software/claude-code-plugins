---
bump: patch
---

### Fixed

- The `lefthook` refusal on the `ci-context` and `review-threads` rows now covers every file lefthook
  reads its config or hook scripts from, not only the root `lefthook.yml`, so fix-ci and
  address-feedback cannot change a hook through `lefthook-local.yaml`, `.config/lefthook.toml` or
  `.lefthook/`.
