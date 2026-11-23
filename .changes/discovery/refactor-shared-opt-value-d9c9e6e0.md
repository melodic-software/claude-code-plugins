---
bump: patch
---

### Changed

- `scripts/check-dispatch-artifact.sh` takes its option-value guard from the shared `lib/opt-value.sh`: an empty or `-`-leading value for `--index-name`, `--newer-than`, `--expect-index` or `--expect-sidecars` is now a usage error (exit 2, as before), and the message reads `check-dispatch-artifact.sh: <option> requires a value`.
