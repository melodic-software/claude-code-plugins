#Requires -Version 7.4
<#
.SYNOPSIS
Shared BeforeAll preamble for the machine-health Pester suites.

.DESCRIPTION
Every suite under tests/windows/ opens with the same path derivation: the tests
root, the skill root above it, the scripts/windows/lib directory, the script
under test, and dot-sources of the lib files and helpers the suite needs. All of
it lives here so the hop counts and the relative layout are written once.

Dot-source this file from a BeforeAll block -- do NOT convert it to a module.
The lib files have to land in the test file's own session state so the suite can
call them and so Pester's Mock intercepts the commands they reach for; a module
would put them in module session state instead. Dot-sourcing runs every
statement below in the caller's scope, which is where the nested dot-sources,
the $script: paths and the generated wrapper all need to land.

.PARAMETER Check
Name of the script under scripts/windows/checks, without the .ps1 extension, to
put in $script:ScriptPath. A check suite also gets Assert-CheckResult
dot-sourced, because every one of them asserts the CheckResult schema.

.PARAMETER Remediation
Name of the script under scripts/windows/remediations, without the .ps1
extension, to put in $script:ScriptPath.

.PARAMETER AsObject
Name of a no-argument wrapper function to define around
Invoke-CheckScriptAsObject $script:ScriptPath. Suites whose wrapper takes
arguments, or invokes something other than the script path, define their own.

.PARAMETER LibScript
File names under scripts/windows/lib to dot-source, in order.

.PARAMETER MockHelpers
Import tests/helpers/Mock-Helpers.psm1.
#>
param(
    [string] $Check = '',
    [string] $Remediation = '',
    [string] $AsObject = '',
    [string[]] $LibScript = @(),
    [switch] $MockHelpers
)

$script:TestsRoot = Split-Path -Parent $PSScriptRoot
$script:SkillRoot = Split-Path -Parent $script:TestsRoot
$script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'

if ($Check) {
    $script:ScriptPath = Join-Path $script:SkillRoot "scripts\windows\checks\$Check.ps1"
    . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
} elseif ($Remediation) {
    $script:ScriptPath = Join-Path $script:SkillRoot "scripts\windows\remediations\$Remediation.ps1"
}

foreach ($libFile in $LibScript) {
    . (Join-Path $script:LibRoot $libFile)
}

if ($MockHelpers) {
    Import-Module (Join-Path $script:TestsRoot 'helpers\Mock-Helpers.psm1') -Force
}

if ($Check -or $Remediation) {
    . (Join-Path $script:TestsRoot 'helpers\Invoke-CheckScript.ps1')
}

if ($AsObject) {
    Set-Item -Path "function:$AsObject" -Value { Invoke-CheckScriptAsObject $script:ScriptPath }
}
