#Requires -Version 7.4
<#
.SYNOPSIS
GitHub Actions workflow-command annotation helpers for Pester runners.

.DESCRIPTION
Dot-sourced by Pester runner scripts; consumers derive on demand via the repo
dep-graph edge scan (tools/AGENTS.md "Vertical slices"). Exposes three
functions used to translate Pester failure records into safe GitHub Actions
`::error::` workflow commands and matching markdown step-summary lines.

Workflow-command payloads require escaping: '%' -> '%25', CR -> '%0D',
LF -> '%0A'. Property values (title= etc.) additionally need ':' -> '%3A'
and ',' -> '%2C'. Without this, untrusted text in test failure messages can
terminate or inject workflow commands. Ref:
https://docs.github.com/en/actions/reference/workflow-commands-for-github-actions

Library file: no Set-StrictMode or $ErrorActionPreference (dot-sourcing leaks
to caller; entry-point sets these). #Requires is a harmless minimum-version
check.

.EXAMPLE
. (Join-Path $repoRoot 'tools/shared/pester/PesterWorkflowAnnotation.ps1')
$info = Get-FailedTestInfo -Test $failedTest
$safeTitle = ConvertTo-WorkflowCommandProperty ('Pester: ' + $info.Path)
$safeMessage = ConvertTo-WorkflowCommandMessage $info.Message
Write-Output "::error title=${safeTitle}::${safeMessage}"
#>

function ConvertTo-WorkflowCommandMessage {
    param([string] $Value)
    if ($null -eq $Value) { return '' }
    return ($Value -replace '%', '%25' -replace "`r", '%0D' -replace "`n", '%0A')
}

function ConvertTo-WorkflowCommandProperty {
    param([string] $Value)
    if ($null -eq $Value) { return '' }
    return ((ConvertTo-WorkflowCommandMessage $Value) -replace ':', '%3A' -replace ',', '%2C')
}

# Extract (path, message) from a Pester failed-test record. Shared between
# the workflow-command annotation loop and the markdown step-summary loop.
function Get-FailedTestInfo {
    param([Parameter(Mandatory)] $Test)
    $path = if ($Test.ExpandedPath) { $Test.ExpandedPath } else { $Test.Name }
    $msg = if ($Test.ErrorRecord -and $Test.ErrorRecord.Exception) {
        $Test.ErrorRecord.Exception.Message
    } else { '(no error message)' }
    return [pscustomobject]@{ Path = $path; Message = $msg }
}
