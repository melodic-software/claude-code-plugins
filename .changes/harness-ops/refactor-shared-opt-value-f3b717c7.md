---
bump: patch
---

### Changed

- `changelog-status.sh` and `normalize-enabled-plugins.sh` take their option-value guard from the shared `lib/opt-value.sh`. changelog-status keeps exit 3 for a usage error, now also refuses a `-`-leading option value, and says `changelog-status.sh: <option> requires a value`.
