# Testing conventions (machine-health)

Pester v5 is the authoritative test framework. This document governs test conventions *within* the machine-health skill; it makes the suite self-contained and portable with the plugin.

## Prerequisites

- **pwsh 7.4+** - both the tests and the skill scripts require PowerShell 7.4+ (`#Requires -Version 7.4`); the orchestrator and checks use 7.x-only syntax, so Windows PowerShell 5.1 is not supported.
- **Pester 5.x** - install via `Install-Module Pester -MinimumVersion 5.7 -Scope CurrentUser -Force` (check with `Get-Module Pester -ListAvailable`).
- **PSScriptAnalyzer** - tests should pass `Invoke-ScriptAnalyzer` clean when the consuming repo lints PowerShell.

## Directory layout

```text
machine-health/
  tests/
    Invoke-MachineHealthTests.ps1        # Runner entry point
    PesterConfiguration.psd1             # Pester config (coverage on, verbose on failure)
    windows/                             # OS-specific test files
      Test-DiskHealth.Tests.ps1
      Test-Defender.Tests.ps1
      ... one .Tests.ps1 per script ...
      integration/                       # Real-Start-Job end-to-end tests
    fixtures/
      windows/
        Get-Volume/                      # Directory per captured cmdlet
          healthy-ssd.clixml
          recovery-partition.clixml
          low-free-space.clixml
        Get-PhysicalDisk/
        Get-MpComputerStatus/
        Get-WinEvent/
        Get-Service/
        winget-upgrade-text/             # .txt for text-output cmdlets
    helpers/
      New-Fixture.ps1                    # Capture helper
      Invoke-FixtureRedaction.ps1        # Scrubs machine-specific values
      Mock-Helpers.psm1                  # Reusable mock factories
```

`Assert-CheckResult.ps1` lives in `scripts/windows/lib/` (not `tests/helpers/`) because `Write-HealthResult` calls it at emit time to enforce the CheckResult schema. Tests dot-source it from same lib path.

## Fixtures - captured + redacted, tracked in git

**Fixtures are tracked in source control.** Reasoning: reproducible tests across contributor machines, no "works on my box" drift, offline testability. Size budget: ~50KB per fixture file, ~500KB total per script's fixture directory.

Capture workflow (`New-Fixture.ps1`):

1. Invoke the target cmdlet against the current host.
2. Serialize via `Export-Clixml -Depth 5`.
3. Pipe through `Invoke-FixtureRedaction` - scrubs:
   - `$env:USERNAME` -> `__USERNAME__`
   - `$env:COMPUTERNAME` -> `__HOSTNAME__`
   - Drive letters -> `__DRIVE__` (when not the fixture's subject)
   - Disk/volume serials and unique IDs -> deterministic placeholders
   - MAC addresses -> `00-00-00-00-00-00`
4. Write to `tests/fixtures/windows/<Cmdlet>/<scenario>.clixml`.
5. A `README.md` in each cmdlet fixture directory describes each scenario.

Synthetic fixtures (no host capture needed) live in same directory, hand-authored as `*.synthetic.clixml` to distinguish them.

## Test file conventions

One `*.Tests.ps1` per script. Naming mirrors source: `checks/Test-DiskHealth.ps1` -> `tests/windows/Test-DiskHealth.Tests.ps1`.

```powershell
#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot '..\..\scripts\windows\checks\Test-DiskHealth.ps1'
    $script:FixtureRoot = Join-Path $PSScriptRoot '..\fixtures\windows'
    $script:LibRoot = Join-Path $PSScriptRoot '..\..\scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
    Import-Module (Join-Path $PSScriptRoot '..\helpers\Mock-Helpers.psm1') -Force
}

Describe 'Test-DiskHealth' {
    Context 'volume filter' {
        It 'excludes unlettered recovery partitions from severity computation' {
            Mock Get-Volume { Import-Clixml (Join-Path $script:FixtureRoot 'Get-Volume\recovery-partition.clixml') }
            Mock Get-PhysicalDisk { Import-Clixml (Join-Path $script:FixtureRoot 'Get-PhysicalDisk\healthy-nvme.clixml') }

            $result = & $script:ScriptPath | ConvertFrom-Json
            Assert-CheckResult $result
            $result.severity | Should -Be 'OK'
            $result.detail.volumes | Should -HaveCount 1  # only the lettered one
            $result.detail.volumes[0].drive | Should -Be 'C'
        }
    }
}
```

## Mocking rules

### Default: block-scoped mocks at script scope

Since skill scripts are **dot-sourced, not module-imported**, standard `Mock <CmdletName>` inside `BeforeAll` / `It` blocks works. Pester v5 mocks are block-scoped by default, not Describe-wide.

### When the mock target is in a module

Wrapper libs (e.g., `Get-CisaKevCache` imported via module) may need `Mock -ModuleName` scoping. Consult `about_Pester` if standard mocking doesn't intercept.

### Never mock the system under test

The script being tested (e.g., `Test-DiskHealth.ps1`) is invoked directly. Only its dependencies (Get-Volume, Get-PhysicalDisk, Get-StorageReliabilityCounter) are mocked.

### Mock factories

`helpers/Mock-Helpers.psm1` provides:

- `New-MockVolume -DriveLetter <char> -FileSystem <str> -SizeGB <num> -FreeGB <num>`
- `New-MockPartition -Type <str> -DriveLetter <char>`
- `New-MockPhysicalDisk -HealthStatus <str> -MediaType <str>`
- `New-MockService -Name <str> -StartType <str> -Status <str>`
- `New-MockEventLogRecord -Provider <str> -Id <int> -TimeCreated <dt>`
- `New-MockDefenderComputerStatus` — shapes `Get-MpComputerStatus` output
- `New-MachineHealthTempDir` / `Remove-MachineHealthTempDir` — per-test scratch dirs

Use these in preference to inline `[pscustomobject]@{}` for consistency.

## Test organization

- **Unit tests** - mock all external calls, run in-process, no Start-Job. Fast.
- **Integration tests** - invoke `Invoke-MachineHealthCheck.ps1` with a temp `-OutputBase`, specific checks enabled. Real Start-Job. Slower. One per check, in `tests/windows/integration/`.
- **Contract tests** - every check's output validates against `catalog/schemas/check-result.schema.json` via `Assert-CheckResult`. Implicit in every unit test.

## Coverage targets

Initial goal: **80% line coverage** per check script. Lower bar fine for:

- Pure delegation (calling a mocked cmdlet and returning its result unchanged)
- Catch-block-only paths that wrap exception types we don't model

Higher bar required for:

- Severity computation (every threshold branch must have a test)
- Output schema construction (every field must be asserted in at least one test)

## Running tests

From a clone of the marketplace repository:

```powershell
# All tests
pwsh -NoProfile -File plugins/machine-health/skills/check/tests/Invoke-MachineHealthTests.ps1

# Single check
pwsh -NoProfile -File plugins/machine-health/skills/check/tests/Invoke-MachineHealthTests.ps1 -Filter 'Test-DiskHealth'

# With coverage
pwsh -NoProfile -File plugins/machine-health/skills/check/tests/Invoke-MachineHealthTests.ps1 -Coverage
```

## Fixture refresh

Fixtures can go stale (new Windows versions, new cmdlet output fields). Refresh workflow:

```powershell
pwsh -File tests/helpers/New-Fixture.ps1 -Cmdlet Get-Volume -Scenario healthy-ssd
# Inspect the redacted output, commit
```

Refresh cadence: opportunistic. When a test fails and investigation reveals the cmdlet's shape changed, refresh that fixture.

## What this skill's tests do NOT do

- **No tests of the Windows OS itself.** We test our code's response to Windows output, not Windows's correctness.
- **No tests of PSScriptAnalyzer rules.** That's the linter's job.
- **No tests of Pester itself.** Pester is a dependency.
- **No performance tests.** 90-second per-check timeout is enforced by the orchestrator.

These conventions apply locally to machine-health; a consuming repo's own PowerShell test standards govern anything outside this plugin.
