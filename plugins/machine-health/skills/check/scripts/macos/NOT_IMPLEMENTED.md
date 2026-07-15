# machine-health — macOS scripts not yet implemented

Scaffolding placeholder. Eventually contains:

```
scripts/macos/
├── Invoke-MachineHealthCheck.ps1   # orchestrator
├── checks/Test-*.ps1        # one per catalog entry with os: ["macos"]
├── remediations/*.ps1       # only those authorized by references/macos/remediation-policy.md
└── lib/                     # Write-HealthResult, Read-HistoryJsonl, etc.
```

## Contract for the skill runtime

When `machine-health` is invoked on macOS:

1. Skill detects `$IsMacOS` (or `uname -s` → `Darwin`).
2. Reads both `references/macos/NOT_IMPLEMENTED.md` and this file.
3. Produces an `UNKNOWN`-severity report (`id: "os-support"`, `category: "platform"`) with one-line summary and pointer to the porting checklist in `references/macos/NOT_IMPLEMENTED.md`.
4. Exits cleanly — **do not attempt to execute any script from `scripts/windows/` on macOS.** Those scripts call Windows-only cmdlets and fail noisily.

## Porting guidance

See `../../references/macos/NOT_IMPLEMENTED.md` for the full porting checklist. Short version:

- Semantics stay in `references/shared/` — no changes.
- Add `references/macos/check-catalog.md` and `references/macos/remediation-policy.md`.
- Write `scripts/macos/Invoke-MachineHealthCheck.ps1` mirroring Windows orchestrator responsibilities.
- Write one `checks/Test-*.ps1` per seeded catalog entry (port each Windows check to its macOS equivalent; mark not-applicable checks with rationale in the catalog).
- PowerShell 7 runs natively on macOS; check scripts stay in PowerShell for language parity with Windows. Helpers in `lib/` copy with near-zero changes.

Remove this file once the folder has a working orchestrator and all eight seeded checks have macOS analogs (or explicit "not applicable" decisions).
