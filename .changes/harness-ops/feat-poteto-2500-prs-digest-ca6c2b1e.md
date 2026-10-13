---
bump: patch
---

### Fixed

- **`scripts/fetch-docs.sh` runs its address check and interpreter probe with `python -I`**, so a module planted in the working directory (an `ipaddress.py`, say) is never imported by the `--public-only` check.
