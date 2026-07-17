# machine-health — Linux scripts not yet implemented

Scaffolding placeholder. Eventually contains:

```
scripts/linux/
├── Invoke-MachineHealthCheck.ps1   # orchestrator (PowerShell 7 on Linux; bash acceptable for checks)
├── checks/Test-*.ps1        # one per catalog entry with os: ["linux"]
├── remediations/*.ps1       # only those authorized by references/linux/remediation-policy.md
└── lib/                     # Write-HealthResult, Read-HistoryJsonl, etc.
```

## Contract for the skill runtime

When `machine-health` is invoked on Linux:

1. Skill detects `$IsLinux` (or `uname -s` → `Linux`).
2. Reads both `references/linux/NOT_IMPLEMENTED.md` and this file.
3. Produces an `UNKNOWN`-severity report (`id: "os-support"`, `category: "platform"`) with one-line summary and pointer to the porting checklist in `references/linux/NOT_IMPLEMENTED.md`.
4. Exits cleanly — **do not attempt to execute any script from `scripts/windows/` on Linux.** Those scripts call Windows-only cmdlets and fail noisily.

## Porting guidance

See `../../references/linux/NOT_IMPLEMENTED.md` for the full porting checklist. Linux-specific notes:

- **Distro variance is first-class.** Parse `/etc/os-release` and dispatch package-manager checks accordingly. Consider a `distro` field in catalog entries for narrow-scope checks.
- **Language choice per check is flexible.** PowerShell 7 on Linux is fine; bash checks are also acceptable provided they emit the schema from `references/shared/output-schema.md`. Orchestrator invokes the script and captures stdout; interpreter is irrelevant.
- **Never assume sudo.** Elevation-required checks return `UNKNOWN` with `needs_admin: true`. No interactive prompts, no `sudo -n` (can still prompt under certain policies).

Remove this file once the folder has a working orchestrator and all eight seeded checks have Linux analogs (or explicit "not applicable" decisions).
