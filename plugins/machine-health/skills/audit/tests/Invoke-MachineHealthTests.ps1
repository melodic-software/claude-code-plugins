#Requires -Version 7.4
<#
.SYNOPSIS
Pester v5 test runner for the machine-health skill.

.DESCRIPTION
Runs all Pester tests under tests/<os>/ for the current OS. Loads config from
PesterConfiguration.psd1. Supports filtering to a single script and optional
code coverage collection.

.PARAMETER Filter
Wildcard applied to the test file name (e.g., 'Test-DiskHealth' runs
Test-DiskHealth.Tests.ps1 only).

.PARAMETER Coverage
Enable code coverage collection. Adds ~2x to runtime.

.PARAMETER Integration
Include integration tests under tests/<os>/integration/. Slower -- invokes the
orchestrator through real Start-Job. Excluded by default.

.PARAMETER ListOnly
Discover tests and print the file list without executing.

.EXAMPLE
pwsh -NoProfile -File tests/Invoke-MachineHealthTests.ps1
Runs all unit tests for the current OS.

.EXAMPLE
pwsh -NoProfile -File tests/Invoke-MachineHealthTests.ps1 -Filter Test-DiskHealth
Runs only Test-DiskHealth.Tests.ps1.

.EXAMPLE
pwsh -NoProfile -File tests/Invoke-MachineHealthTests.ps1 -Coverage
Runs all tests with coverage collection.
#>
[CmdletBinding()]
param(
    [string] $Filter,
    [switch] $Coverage,
    [switch] $Integration,
    [switch] $ListOnly
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function New-DirectoryIfMissing {
    param([Parameter(Mandatory)] [string] $Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Get-ErrorRecordMessage {
    param([Parameter(Mandatory)] $ErrorRecord)
    if ($ErrorRecord.Exception) { $ErrorRecord.Exception.Message } else { "$ErrorRecord" }
}

# Emit one workflow-command annotation. Collapse to one line and escape here, so no
# call site can end (CR/LF) or inject a workflow command.
function Write-WorkflowError {
    param(
        [Parameter(Mandatory)] [string] $Title,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Message
    )
    $safeTitle = ConvertTo-WorkflowCommandProperty $Title
    $safeMessage = ConvertTo-WorkflowCommandMessage ($Message -replace "`r?`n", ' | ')
    Write-Output("::error title=${safeTitle}::${safeMessage}")
}

# Append a multi-line message to the step summary as an indented fenced block.
function Add-FencedBlock {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[string]] $Lines,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text
    )
    $Lines.Add('  ```')
    foreach ($ln in ($Text -split "`r?`n")) { $Lines.Add("  $ln") }
    $Lines.Add('  ```')
}

# The suites target Pester v5 and ModuleVersion is only a minimum, so cap the major
# or a side-by-side v6 install would be imported instead.
$minPester = [version]'5.7.0'
$maxPester = [version]'5.99.99'
$pester = Get-Module Pester -ListAvailable |
    Where-Object { $_.Version -ge $minPester -and $_.Version -le $maxPester }
if (-not $pester) {
    $install = "Install-Module Pester -MinimumVersion $minPester -MaximumVersion $maxPester -Scope CurrentUser -Force"
    Write-Error "Pester v5 ($minPester+) required. $install"
    exit 1
}
Import-Module Pester -MinimumVersion $minPester -MaximumVersion $maxPester -Force

$os = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'windows' }
elseif ($IsMacOS) { 'macos' }
elseif ($IsLinux) { 'linux' }
else { 'unknown' }

if ($os -eq 'unknown') {
    Write-Error 'Unsupported OS; Pester tests not runnable.'
    exit 1
}

$testsRoot = $PSScriptRoot
$osRoot = Join-Path $testsRoot $os
if (-not (Test-Path -LiteralPath $osRoot)) {
    Write-Warning "No tests directory for OS: $osRoot"
    exit 0
}

$testFiles = Get-ChildItem -LiteralPath $osRoot -Recurse -Filter '*.Tests.ps1' -File
if (-not $Integration) {
    $testFiles = $testFiles | Where-Object { $_.Directory.Name -ne 'integration' }
}
if (-not $testFiles) {
    Write-Warning 'No test files found.'
    exit 0
}
if ($Filter) {
    $testFiles = $testFiles | Where-Object { $_.BaseName -like "*$Filter*" }
}

if ($ListOnly) {
    $testFiles | ForEach-Object { $_.FullName }
    return
}

if (-not $testFiles) {
    Write-Warning 'No test files matched.'
    exit 0
}

$configPath = Join-Path $testsRoot 'PesterConfiguration.psd1'
$configHash = Import-PowerShellDataFile -LiteralPath $configPath
$config = New-PesterConfiguration -Hashtable $configHash
$config.Run.Path = $testFiles.FullName

# Test-result root: the enclosing git working tree, else a machine-health folder under
# TEMP (an installed plugin cache is not a git repo).
$repoRoot = (git -C $testsRoot rev-parse --show-toplevel 2>$null)
if (-not $repoRoot) {
    $repoRoot = Join-Path ([System.IO.Path]::GetTempPath()) 'machine-health'
}

. (Join-Path $testsRoot 'helpers\PesterWorkflowAnnotation.ps1')

# Absolutize OutputPath, which Pester resolves against the CWD. Read it from the plain
# hashtable: the typed property's ToString() embeds help text and breaks Split-Path.
$testResultPath = Join-Path $repoRoot $configHash.TestResult.OutputPath
$config.TestResult.OutputPath = $testResultPath
New-DirectoryIfMissing -Path $testResultPath

if ($Coverage) {
    $config.CodeCoverage.Enabled = $true
    $skillRoot = Split-Path -Parent $testsRoot
    $config.CodeCoverage.Path = @(
        Join-Path $skillRoot "scripts/$os/checks"
        Join-Path $skillRoot "scripts/$os/lib"
        Join-Path $skillRoot "scripts/$os/remediations"
    )
    $covPath = Join-Path $repoRoot $configHash.CodeCoverage.OutputPath
    $config.CodeCoverage.OutputPath = $covPath
    New-DirectoryIfMissing -Path $covPath
}

$result = Invoke-Pester -Configuration $config

# Under GitHub Actions only, emit workflow-command annotations for failures so they
# surface on the check run page, readable via the API without raw log access.

if ($env:GITHUB_ACTIONS -eq 'true' -and $result.FailedCount -gt 0) {
    Write-Output('')
    Write-Output("::group::Pester failure summary ($($result.FailedCount) failed)")
    foreach ($t in $result.Failed) {
        $info = Get-FailedTestInfo -Test $t
        Write-WorkflowError -Title ('Pester: ' + $info.Path) -Message $info.Message
    }
    Write-Output('::endgroup::')

    # BeforeAll/Container failures live in a different collection than failed tests. A $null
    # Containers still sends one $null through Where-Object, tripping StrictMode, so guard it.
    $failedContainers = @()
    if ($result.Containers) {
        $failedContainers = @($result.Containers | Where-Object { $_.Result -eq 'Failed' -and $_.ErrorRecord })
    }
    foreach ($c in $failedContainers) {
        foreach ($err in $c.ErrorRecord) {
            Write-WorkflowError -Title ('Pester-Container: ' + $c.Item) `
                -Message (Get-ErrorRecordMessage $err)
        }
    }

    # Also render it to the job summary; $env:GITHUB_STEP_SUMMARY is a file the runner
    # appends to the job's Summary tab.
    if ($env:GITHUB_STEP_SUMMARY -and (Test-Path -LiteralPath $env:GITHUB_STEP_SUMMARY)) {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('## Pester failure summary')
        $lines.Add('')
        $counts = "$($result.FailedCount) failed / $($result.PassedCount) passed / $($result.SkippedCount) skipped"
        $lines.Add("**$counts**")
        $lines.Add('')
        if ($result.Failed.Count -gt 0) {
            $lines.Add('### Failed tests')
            $lines.Add('')
            foreach ($t in $result.Failed) {
                $info = Get-FailedTestInfo -Test $t
                $lines.Add("- **$($info.Path)**")
                Add-FencedBlock -Lines $lines -Text $info.Message
            }
        }
        if ($failedContainers.Count -gt 0) {
            $lines.Add('### Failed containers (BeforeAll / discovery)')
            $lines.Add('')
            foreach ($c in $failedContainers) {
                $lines.Add("- **$($c.Item)**")
                foreach ($err in $c.ErrorRecord) {
                    Add-FencedBlock -Lines $lines -Text (Get-ErrorRecordMessage $err)
                }
            }
        }
        Add-Content -LiteralPath $env:GITHUB_STEP_SUMMARY -Value ($lines -join "`n") -Encoding utf8
    }
}

exit $result.FailedCount
