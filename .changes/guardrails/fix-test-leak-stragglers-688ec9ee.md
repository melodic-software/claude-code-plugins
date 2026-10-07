---
bump: patch
---

### Changed

- **Test suite only; nothing shipped changes.** The no-jq cases of `run-guards.test.sh` and `block-hook-bypass.test.sh` no longer hide a failed `ln -s` behind `2>/dev/null || true`: the first failed native link prints its error and the group reports a visible SKIP instead of running against an empty shim. No copy fallback.
