---
bump: patch
---

### Changed

- Intake triage no longer holds an issue for cost when the work only spends from a flat or prepaid source: model runs, lane runs and `claude plugin eval` passes bill the prepaid API keys, which do not auto-refill (owner Q37). Only a new or renewing charge (Actions billing, Azure, a key or plan that renews or auto-recharges) is cost (`.github/workflows/intake-triage.yml`).
