#Requires -Version 7.4
<#
.SYNOPSIS
Captures real cmdlet output as a redacted Pester fixture.

.DESCRIPTION
Wraps a one-off cmdlet invocation so its output can be reused as deterministic
test input. Runs redaction via Invoke-FixtureRedaction before serializing. Writes
to tests/fixtures/<os>/<Cmdlet>/<Scenario>.clixml.

Fixtures are tracked in git. Review the redacted output before committing.

.PARAMETER Cmdlet
Cmdlet to invoke. Must be a read-only inspection cmdlet (Get-*, etc.).

.PARAMETER Scenario
Short kebab-case label describing the state captured (e.g., 'healthy-ssd',
'recovery-partition').

.PARAMETER Arguments
Optional argument list forwarded to the cmdlet via splatting. Use a hashtable.

.PARAMETER PreserveDriveLetter
Drive letter (if any) that is the intentional subject of this fixture. Kept
verbatim while other drive letters are redacted to __DRIVE__.

.PARAMETER OverwriteExisting
Allow overwriting a fixture that already exists.

.EXAMPLE
pwsh -File tests/helpers/New-Fixture.ps1 -Cmdlet Get-Volume -Scenario all-volumes

.EXAMPLE
pwsh -File tests/helpers/New-Fixture.ps1 -Cmdlet Get-MpComputerStatus -Scenario healthy
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $Cmdlet,
    [Parameter(Mandatory)] [ValidatePattern('^[a-z][a-z0-9-]*[a-z0-9]$')] [string] $Scenario,
    [hashtable] $Arguments = @{},
    [char] $PreserveDriveLetter = [char]0,
    [switch] $OverwriteExisting
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Invoke-FixtureRedaction.ps1')

if (-not (Get-Command $Cmdlet -ErrorAction SilentlyContinue)) {
    throw "Cmdlet '$Cmdlet' not found."
}

$os = if ($IsWindows -or $env:OS -eq 'Windows_NT') { 'windows' }
elseif ($IsMacOS) { 'macos' }
elseif ($IsLinux) { 'linux' }
else { throw 'Unsupported OS for fixture capture.' }

$fixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath '..\fixtures' -AdditionalChildPath $os, $Cmdlet
if (-not (Test-Path -LiteralPath $fixtureRoot)) {
    New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
}

$fixturePath = Join-Path -Path $fixtureRoot -ChildPath "$Scenario.clixml"
if ((Test-Path -LiteralPath $fixturePath) -and -not $OverwriteExisting) {
    throw "Fixture already exists at $fixturePath. Pass -OverwriteExisting to replace."
}

Write-Verbose "Invoking $Cmdlet with args $($Arguments | ConvertTo-Json -Compress)"
$raw = & $Cmdlet @Arguments
$redacted = Invoke-FixtureRedaction -InputObject $raw -PreserveDriveLetter $PreserveDriveLetter

if ($PSCmdlet.ShouldProcess($fixturePath, "Write redacted fixture ($($raw.Count) items)")) {
    $redacted | Export-Clixml -LiteralPath $fixturePath -Depth 5
    Write-Information "Wrote fixture: $fixturePath" -InformationAction Continue
    $reviewNote = 'Review the file before committing. Sensitive values should be replaced with __*__ placeholders.'
    Write-Information $reviewNote -InformationAction Continue
}
