#Requires -Version 7.4
<#
.SYNOPSIS
Shared "run a check script and read its JSON back" helper for the Pester suites.

.DESCRIPTION
Every check script emits one compact JSON document on stdout. Reading it back
takes the same three steps in every suite: invoke the script, drop the empty
elements PowerShell leaves in the collected output stream, and parse the join as
JSON. All three live here so the shape is defined once.

Dot-source this file from a BeforeAll block -- do NOT convert it to a module.
Pester installs mocks into the test file's session state, and a check script
invoked from module session state runs against the REAL commands instead of the
mocks (verified: a test-scope Mock did not intercept a script invoked through a
module function).

Suites whose wrapper needs extra arguments or a non-JSON mode call
ConvertFrom-CheckOutput on the raw output directly.
#>

function ConvertFrom-CheckOutput {
    [CmdletBinding()]
    param([Parameter(Position = 0)] $RawOutput)
    $json = ($RawOutput | Where-Object { $_ }) -join "`n"
    return $json | ConvertFrom-Json
}

function Invoke-CheckScriptAsObject {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, Position = 0)] [string] $Path)
    return ConvertFrom-CheckOutput (& $Path)
}
