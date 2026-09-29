#Requires -Version 7.4

<#
.SYNOPSIS
Shared result envelope for a Windows health check. Dot-source it; do not call it.

.DESCRIPTION
The check sets $id, $category, $commands, $FailureSummary, and $CheckBody, then
dot-sources this file. Dot-sourcing is the point: the body then runs in the
check's own scope, which is where Pester installs mocks. A function call would
put the body in a scope those mocks do not reach.

The envelope owns the stopwatch, the outer catch, the UNKNOWN fallback, the
duration stamp, and (unless $PassThru) the result write. $CheckBody assigns
$result. A throw, or a body that leaves $result unset, becomes
New-HealthFailureResult with $FailureSummary. $FailureNeedsAdmin and
$FailureAdminFields are optional and default to the same omission the checks
used to write in their own catch.

$sw is the running clock. A body that budgets its own walk reads that same
stopwatch.

$PassThru stamps the duration and leaves $result for the caller to return.
Test-Drivers tests pass it so they can read the object. The script entry
point does not, so this file still writes the result.

Every check except Test-Drivers sets `$PassThru = $false` before dot-sourcing.
The envelope reads $PassThru through session state, which also walks parent
scopes, so the line stops a caller's $PassThru from leaking in and suppressing
the write. Test-Drivers declares -PassThru as a parameter instead.
#>

# Variable lookups go through the session state, not Test-Path: check suites
# mock Test-Path, and a mocked Test-Path would read every optional variable as
# unset and every result as missing.
$envelopeVars = $ExecutionContext.SessionState.PSVariable
$FailureNeedsAdmin = [bool]$envelopeVars.GetValue('FailureNeedsAdmin')
$PassThru = [bool]$envelopeVars.GetValue('PassThru')
$Human = [bool]$envelopeVars.GetValue('Human')

# $sw is the name check bodies already use for the running clock.
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    . $CheckBody
    if ($null -eq $envelopeVars.GetValue('result')) {
        throw "Check $id produced no health result."
    }
} catch {
    $failure = @{
        Id          = $id
        Category    = $category
        Summary     = $FailureSummary
        Commands    = $commands
        ErrorRecord = $_
        NeedsAdmin  = [bool]$FailureNeedsAdmin
    }
    $adminFields = $envelopeVars.GetValue('FailureAdminFields')
    if ($null -ne $adminFields) {
        $failure.AdminFields = $adminFields
    }
    $result = New-HealthFailureResult @failure
}

if ($PassThru) {
    $sw.Stop()
    $result.duration_ms = [int]$sw.ElapsedMilliseconds
} else {
    Complete-HealthCheck -Result $result -Stopwatch $sw -Human:$Human
}
