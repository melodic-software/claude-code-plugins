# machine-health — Linux is not yet implemented

Scaffolding placeholder. When `machine-health` is invoked on a Linux host, the skill **must** emit a clear `UNKNOWN`-severity report explaining this gap and **must not** attempt to execute scripts from `scripts/windows/` on Linux.

## What the skill should do on Linux today

1. Detect OS: `$IsLinux -eq $true` (PowerShell 7+) or `uname -s` returns `Linux`.
2. Load `references/shared/*.md` for semantics, schema, and discovery guidance.
3. Read this file; note `scripts/linux/NOT_IMPLEMENTED.md` is also present.
4. Produce a single-check report:
   - `id: "os-support"`, `category: "platform"`, `severity: "UNKNOWN"`.
   - `summary: "Linux support is scaffolded but not yet implemented."`
   - `commands`: one-liner pointing at this file for porting guidance.
5. Exit cleanly. No process spawned against Windows scripts. No install attempts. No network calls.

## Porting checklist

Goal is "populate two folders," not "refactor the skill." Everything under `references/shared/` stays the same; OS-agnostic by design.

1. **Read the shared references** in order:
   - `references/shared/severity-rubric.md` — inherits the five levels and the trend rule.
   - `references/shared/output-schema.md` — every Linux check must emit this exact schema.
   - `references/shared/report-template.md` — report renderer is already OS-agnostic.
   - `references/shared/discovery-guide.md` — **Linux** section lists candidate dimensions to probe (apt/dnf/pacman state, systemd unit failures, journalctl boot errors, smartctl, LUKS status, snap/flatpak, container engine disk usage, cert expiry).
   - `references/shared/remediation-philosophy.md` — posture (fail-safe, one attempt, forbidden actions) is universal.
2. **Populate `references/linux/`** with:
   - `check-catalog.md` — Linux equivalent. Account for distro variance: orchestrator must detect distro family (`/etc/os-release`) and dispatch checks appropriately (apt on Debian/Ubuntu, dnf on Fedora/RHEL, pacman on Arch, etc.).
   - `remediation-policy.md` — explicit per-remediation authorization. Linux remediations are trickier because a single action can behave differently across distros; err heavily on surface-over-fix.
3. **Populate `scripts/linux/`** with:
   - `Invoke-MachineHealthCheck.ps1` — PowerShell 7 on Linux works fine (`sudo apt-get install -y powershell` on Debian derivatives, etc.). Bash is fine — orchestrator can shell out and still emit the schema.
   - `checks/Test-*.ps1` (or `.sh` equivalents) — one per catalog entry.
   - `remediations/*.ps1` — only what the catalog authorizes.
   - `lib/` — reuse Windows lib shapes.
4. **Seed `catalog/checks.jsonc`** with `os: ["linux"]` entries alongside existing Windows ones. For distro-specific checks, scope with `distro: ["ubuntu", "debian"]` in an additional field the orchestrator filters on.
5. **Validate**: dry-run on a scratch `OutputBase` (e.g., `/tmp/machine-health-smoketest`) with `-DryRun -RunMode first-run`.

## Explicit prohibition

**Do not attempt to execute any script under `scripts/windows/` on Linux.** Windows scripts call `Get-CimInstance Win32_*`, `powercfg`, registry paths, and Windows-only assemblies. Running them on Linux fails in noisy, confusing ways and pollutes the run log.

## A note on sudo

Many interesting Linux checks (SMART, full journalctl, LUKS state) require elevation. Consistent with the skill's Windows posture, **never prompt for sudo** and **never assume sudoers NOPASSWD**. When a check needs elevation and run is unprivileged, emit `UNKNOWN` with `needs_admin: true` — human decides whether to rerun under sudo.

## When to remove this file

Replace this stub only when all of these hold:

- Every check seeded in `references/windows/check-catalog.md` has a Linux analog (or is explicitly marked "not applicable to Linux" in `references/linux/check-catalog.md` with rationale).
- `scripts/linux/Invoke-MachineHealthCheck.ps1` passes the dry-run smoke test against `/tmp/machine-health-smoketest` with `-DryRun -RunMode first-run`.
- Run produces a valid report and a valid `history.jsonl` line.

Until then, this file stays in place and the skill reports `UNKNOWN` on Linux hosts.
