# Native-command invocation has no argv adapter

Recorded park for
[#3423](https://github.com/melodic-software/claude-code-plugins/issues/3423),
a deepening candidate that would add a native-invoker adapter mirroring
`Invoke-AllowlistedWeb`.

## Decision

**Park. Do not hoist.** Native binaries stay spawned inline. The web adapter
stays the web adapter.

- **Option A (taken):** no unpaid hoist. `Get-GpuDriverInfo.ps1`,
  `Get-DriverStoreInventory.ps1`, and `Get-PnpProblemDevices.ps1` keep their
  own `& nvidia-smi` / `& pnputil` calls. Tests keep their own stand-ins. A
  native-invoker that takes a tool name plus an argument array is unpaid.
- **Option B (declined):** one adapter that records the exact argument vector,
  routes `$LASTEXITCODE` non-zero to the documented fallback, and reports a
  tool absent from PATH with the `source` field the check-result schema
  expects.

**Claim:** Windows lib modules that spawn a native binary do so inline. There
is no seam where an argument vector can be observed. `Invoke-AllowlistedWeb`
is the web dependency adapter only. A native-invoker is unpaid.
**Basis:** origin/main as of this record. `& nvidia-smi
'--query-gpu=name,driver_version'` in `Get-GpuDriverInfo.ps1`. `& pnputil
/enum-drivers` in `Get-DriverStoreInventory.ps1`. `& pnputil /enum-devices
/problem` in `Get-PnpProblemDevices.ps1`. Three of 36 files under
`scripts/windows/lib/` spawn a native. #3370 / #3391 (96c8c0a3e) is the
worked argv-shape bug: PowerShell's comma-plus-space spreading split
`--query-gpu=name, driver_version` into four argv entries; the existing
Pester suite asserted around it. `Invoke-AllowlistedWeb.ps1` remains the
precedent for a real adapter, and its suite mocks `Invoke-WebRequest`.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds a native-invoker adapter with a recording stub
that fails an #3370-shaped argv split, and the three native-spawning modules
call it.

## Rationale

- The two-adapter rule still applies. Three native callers is a thin
  population for a new port. The web adapter has one dependency family
  (HTTP) and many callers; native tools do not share one argv contract.
- `Invoke-MachineHealthCheck.ps1` still does not compose a native adapter
  path. Building the adapter without pinning that composition is the unpaid
  second half of the candidate.
- The issue is `work-class: structural` and `needs-human`. Badge on filing
  was Worth exploring, not Strong, for this arithmetic.

## Revisit when

- A maintainer funds the adapter and names the first module to migrate, or
- a new argv-shape defect in a native spawn is missed by a stand-in again.

## Prior requests

- #3423 (2026-09-28): deepening candidate; Option A recorded here.
