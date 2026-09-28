# Windows check envelope stays per-script

Recorded park for
[#3451](https://github.com/melodic-software/claude-code-plugins/issues/3451),
a batch-simplify leftover that would hoist the stopwatch / try-catch /
UNKNOWN fallback / duration restamp envelope shared by the Windows check
family.

## Decision

**Park. Do not hoist.** Each check keeps its own envelope. A body-taking
helper plus a 19-check migration is unpaid.

- **Option A (taken):** no unpaid hoist. Every `scripts/windows/checks/Test-*.ps1`
  starts its own stopwatch, wraps its body in try/catch, falls back to
  `New-HealthFailureResult`, and restamps duration on the way out.
  `Write-HealthResult.ps1` already owns `New-HealthResult`,
  `New-HealthFailureResult`, `Complete-HealthCheck`, and `Write-HealthResult`.
  It does not own "run this body inside the envelope."
- **Option B (declined):** one envelope helper in `scripts/windows/lib`
  that takes a check id and a body, plus a reviewed migration of every
  check onto it, proven on the Windows Pester lane.

**Claim:** the Windows check family keeps a per-script envelope. The shared
library owns result construction and emit, not the stopwatch / try-catch /
UNKNOWN / restamp wrap. A body-taking envelope helper is unpaid.
**Basis:** origin/main as of this record. 19 files under
`scripts/windows/checks/`. All 19 call `[System.Diagnostics.Stopwatch]::StartNew()`
and catch with `New-HealthFailureResult`. 18 close with `Complete-HealthCheck`.
`Test-Drivers.ps1` restamps inside `Invoke-DriversCheck` and pipes to
`Write-HealthResult` because Pester mocks do not reach an `&`-invoked
script, so the file has a dot-source guard. 36 files under
`scripts/windows/lib/`; none is an envelope. `check-catalog.md` already
states the UNKNOWN fallback as a contract. The Windows CI lane is
informational and path-conditional. #3451 is `work-class: structural`
and `needs-human`.
**As of:** 2026-09-28.
**Recheck:** a maintainer funds an envelope helper in
`scripts/windows/lib` that takes a check id and a body, migrates one check
with that check's Pester suite green on the Windows lane (mocks resolving
through the helper), then the remaining 18, including `Test-Drivers.ps1`.

## Rationale

- The emit helpers already exist. What is left is wrapping the body, and
  that wrap is where Pester mock scope lives. `Test-Drivers.ps1` already
  had to leave `Complete-HealthCheck` for that reason.
- The Windows lane is outside the required status aggregate and runs only
  when Windows-affecting paths change. A 19-file migration without a
  funded runner read is unpaid proof, not a sweep.
- The issue title's "10-file" count is stale. The family is 19 checks.

## Revisit when

- A maintainer funds the helper and names the first check to migrate, or
- a correction to UNKNOWN handling or duration stamping has to be patched
  in more than one check at once.

## Prior requests

- #3451 (2026-09-28): batch-simplify leftover; Option A recorded here.
