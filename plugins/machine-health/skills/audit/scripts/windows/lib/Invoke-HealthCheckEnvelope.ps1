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
Test-Drivers uses it so a dot-sourced test can read the object; the script
entry point still pipes that object to Write-HealthResult.
#>

if (-not (Test-Path variable:FailureNeedsAdmin)) { $FailureNeedsAdmin = $false }
if (-not (Test-Path variable:PassThru)) { $PassThru = $false }
if (-not (Test-Path variable:Human)) { $Human = $false }

# $sw is the name check bodies already use for the running clock.
$sw = [System.Diagnostics.Stopwatch]::StartNew()
try {
    . $CheckBody
    if (-not (Test-Path variable:result) -or $null -eq $result) {
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
    if (Test-Path variable:FailureAdminFields) {
        $failure.AdminFields = $FailureAdminFields
    }
    $result = New-HealthFailureResult @failure
}

if ($PassThru) {
    $sw.Stop()
    $result.duration_ms = [int]$sw.ElapsedMilliseconds
} else {
    Complete-HealthCheck -Result $result -Stopwatch $sw -Human:$Human
}
