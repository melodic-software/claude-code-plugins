---
bump: patch
---

### Changed

- `lib/persist-report.sh` and the audit-instructions `emit-findings.sh` take their option-value guard from the shared `lib/opt-value.sh`. persist-report now refuses an empty or `-`-leading option value (exit 2, as before), still reads `--report -` as stdin, and says `persist-report.sh: <option> requires a value`.
