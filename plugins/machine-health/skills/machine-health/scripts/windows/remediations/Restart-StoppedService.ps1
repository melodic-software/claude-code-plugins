#Requires -Version 7.4
<#
.SYNOPSIS
Remediation: one Start-Service attempt per stopped Automatic service.

.DESCRIPTION
Accepts either a single service name via -ServiceName or a full services
CheckResult via -Finding (string or PSCustomObject). Emits a JSON array
of RemediationAttempt objects on stdout -- one per service targeted.

The previous implementation read the finding from [Console]::In, which
is unreliable under Start-Job isolation and some PowerShell hosts. The
orchestrator now passes the finding explicitly via -Finding, matching
the contract used by every other remediation.

Policy: references/windows/remediation-policy.md#1-restart-stoppedservice
Philosophy: references/shared/remediation-philosophy.md
#>
[CmdletBinding(DefaultParameterSetName = 'Finding', SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(ParameterSetName = 'Service')]
    [string]$ServiceName,

    [Parameter(ParameterSetName = 'Finding')]
    $Finding,

    [switch]$Human
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'

function Get-ServiceState {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter(Mandatory = $true)] [string] $Name)

    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        return @{
            name       = $svc.Name
            status     = $svc.Status.ToString()
            start_type = $svc.StartType.ToString()
            exists     = $true
        }
    } catch {
        return @{ name = $Name; exists = $false; error = $_.Exception.Message }
    }
}

function Get-PropertyValue {
    # Strict-mode-safe property accessor: returns $null when the property
    # is absent instead of throwing. Works for PSCustomObject, hashtable,
    # and ordered dictionary values returned by ConvertFrom-Json.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)] $InputObject,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $null
    }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Resolve-FindingTarget {
    [CmdletBinding()]
    [OutputType([object[]])]
    param([Parameter(Mandatory = $false)] $FindingData)

    if ($null -eq $FindingData) { return @() }

    # Any badly-shaped finding -- unparsable JSON, or valid JSON missing
    # .detail / .stopped_auto_services -- yields an empty target list rather
    # than crashing. Property reads go through Get-PropertyValue because under
    # Set-StrictMode 3.0 a bare `$obj.detail` on an absent property throws.
    $obj = $FindingData
    if ($FindingData -is [string]) {
        try {
            $obj = $FindingData | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Verbose ('Resolve-FindingTarget: JSON parse failed. ' +
                $_.Exception.Message)
            return @()
        }
    }

    $detail = Get-PropertyValue -InputObject $obj -Name 'detail'
    if ($null -eq $detail) { return @() }
    $services = Get-PropertyValue -InputObject $detail -Name 'stopped_auto_services'
    if ($null -eq $services) { return @() }
    return @($services)
}

$targets = if ($ServiceName) {
    @([pscustomobject]@{ name = $ServiceName })
} else {
    @(Resolve-FindingTarget -FindingData $Finding)
}

$attempts = [System.Collections.Generic.List[object]]::new()
foreach ($t in $targets) {
    $tName = Get-PropertyValue -InputObject $t -Name 'name'
    $name = $tName ? $tName : "$t"
    $before = Get-ServiceState -Name $name

    $attemptedAt = (Get-Date).ToString('o')
    $err = $null

    if (-not $before.exists) {
        $err = "Service '$name' does not exist."
    } elseif ($before.status -ne 'Running') {
        if ($PSCmdlet.ShouldProcess($name, 'Start-Service')) {
            try {
                Start-Service -Name $name -ErrorAction Stop
                Start-Sleep -Milliseconds 500
            } catch {
                $err = $_.Exception.Message
            }
        } else {
            $err = 'skipped by ShouldProcess'
        }
    }

    $after = Get-ServiceState -Name $name
    $succeeded = ($before.exists -and -not $err -and $after.status -eq 'Running')

    $attempts.Add([ordered]@{
            id           = 'restart-stopped-service'
            target       = $name
            finding_id   = 'services'
            attempted_at = $attemptedAt
            succeeded    = $succeeded
            before       = $before
            after        = $after
            bytes_freed  = $null
            error        = $err
        })
}

if ($Human) {
    foreach ($a in $attempts) {
        $status = if ($a.succeeded) { 'OK' } else { 'FAIL' }
        $beforeStatus = $a.before.status
        $afterStatus = $a.after.status
        Write-Output ("[$status] restart-stopped-service $($a.target) -- " +
            "before=$beforeStatus after=$afterStatus")
        if ($a.error) { Write-Output "  error: $($a.error)" }
    }
} else {
    $attempts | ConvertTo-Json -Depth 10 -Compress
}
