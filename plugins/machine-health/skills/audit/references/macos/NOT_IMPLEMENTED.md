# machine-health — macOS is not yet implemented

Scaffolding placeholder. When `machine-health` is invoked on a macOS host, the skill **must** emit a clear `UNKNOWN`-severity report explaining this gap and **must not** attempt to execute scripts from `scripts/windows/` on macOS.

## What the skill should do on macOS today

1. Detect OS: `$IsMacOS -eq $true` (PowerShell 7+) or `uname -s` returns `Darwin`.
2. Load `references/shared/*.md` for semantics, schema, and discovery guidance.
3. Read this file; note `scripts/macos/NOT_IMPLEMENTED.md` is also present.
4. Produce a single-check report:
   - `id: "os-support"`, `category: "platform"`, `severity: "UNKNOWN"`.
   - `summary: "macOS support is scaffolded but not yet implemented."`
   - `commands`: one-liner pointing at this file for porting guidance.
5. Exit cleanly. No process spawned against Windows scripts. No install attempts. No network calls.

## Porting checklist

Goal is "populate two folders," not "refactor the skill." Everything under `references/shared/` stays the same; OS-agnostic by design.

1. **Read the shared references** in order:
   - `references/shared/severity-rubric.md` — inherits the five levels and the trend rule.
   - `references/shared/output-schema.md` — every macOS check must emit this exact schema.
   - `references/shared/report-template.md` — report renderer is already OS-agnostic.
   - `references/shared/discovery-guide.md` — **macOS** section lists candidate dimensions to probe (Homebrew, FileVault, Keychain expiry, smartctl/system_profiler, kernel panics, etc.).
   - `references/shared/remediation-philosophy.md` — posture (fail-safe, one attempt, forbidden actions) is universal.
2. **Populate `references/macos/`** with:
   - `check-catalog.md` — macOS equivalent of the Windows catalog, thresholds tailored to macOS (e.g., `pmset -g batt` instead of `powercfg /batteryreport`).
   - `remediation-policy.md` — explicit per-remediation authorization, same structure as `references/windows/remediation-policy.md`.
3. **Populate `scripts/macos/`** with:
   - `Invoke-MachineHealthCheck.ps1` — orchestrator, same responsibilities as Windows one. PowerShell 7 runs fine on macOS (`brew install --cask powershell` or pkg installer).
   - `checks/Test-*.ps1` — one per catalog entry. macOS-specific commands: `softwareupdate`, `diskutil`, `fdesetup`, `pmset`, `log show`, `system_profiler`, `security find-identity`.
   - `remediations/*.ps1` — only what the catalog authorizes.
   - `lib/` — reuse Windows lib shapes; `Write-HealthResult.ps1` and `Read-HistoryJsonl.ps1` are essentially OS-agnostic.
4. **Seed `catalog/checks.jsonc`** with `os: ["macos"]` entries alongside existing Windows ones.
5. **Validate**: dry-run on a scratch `OutputBase` exactly as the Windows implementation does (see `SKILL.md` § High-level procedure).

## Explicit prohibition

**Do not attempt to execute any script under `scripts/windows/` on macOS.** Windows scripts call `Get-CimInstance Win32_*`, `powercfg`, registry paths, and PowerShell Windows-only assemblies. Running them on macOS fails in noisy, confusing ways and pollutes the run log. Detection-first, then stub-first — that's the contract.

## When to remove this file

Replace this stub only when all of these hold:

- Every check seeded in `references/windows/check-catalog.md` has a macOS analog (or is explicitly marked "not applicable to macOS" in `references/macos/check-catalog.md` with rationale).
- `scripts/macos/Invoke-MachineHealthCheck.ps1` passes the dry-run smoke test against `$env:TMPDIR/machine-health-smoketest` with `-DryRun -RunMode first-run`.
- Run produces a valid report and a valid `history.jsonl` line.

Until then, this file stays in place and the skill reports `UNKNOWN` on macOS hosts.
