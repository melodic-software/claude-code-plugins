---
bump: minor
---

### Added

- `confirm-verdict.sh` takes an optional `--dir <checkout>` naming the checkout whose common git directory holds the verdict record (`CONFIRM_VERDICT_DIR` still wins). Without `--dir`, it uses the current directory as before.
