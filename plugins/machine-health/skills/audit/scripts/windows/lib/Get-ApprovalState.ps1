#Requires -Version 7.4

<#
.SYNOPSIS
Load the per-user ApprovalState from $StateDir/approvals.json.

.DESCRIPTION
Fail-safe posture: any error (missing file, permission denied, malformed
JSON, schema violation) logs a warning and returns defaults (nothing
approved). A single broken approvals.json must not prevent the rest of
the audit from running. No other file is read: an approval exists only
where Set-ApprovalState wrote it.
#>

. (Join-Path $PSScriptRoot 'Assert-ApprovalState.ps1')
. (Join-Path $PSScriptRoot 'Read-SharedText.ps1')
. (Join-Path $PSScriptRoot 'Write-MachineHealthLog.ps1')

function New-DefaultApprovalState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    return [pscustomobject]@{
        schema_version = '1.0'
        remediations   = [pscustomobject]@{}
    }
}

function Get-ApprovalState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $StateDir,
        [string] $LogPath
    )

    if (-not (Test-Path -LiteralPath $StateDir)) {
        try {
            New-Item -ItemType Directory -Path $StateDir -Force -ErrorAction Stop | Out-Null
        } catch {
            Write-Warning "Get-ApprovalState: unable to create state dir '$StateDir'. $($_.Exception.Message)"
            return (New-DefaultApprovalState)
        }
    }

    $approvalsPath = Join-Path $StateDir 'approvals.json'

    if (Test-Path -LiteralPath $approvalsPath) {
        try {
            $raw = Read-SharedText -Path $approvalsPath
            if ([string]::IsNullOrWhiteSpace($raw)) {
                return (New-DefaultApprovalState)
            }
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
            [void](Assert-ApprovalState $parsed -Because $approvalsPath)
            return $parsed
        } catch {
            Write-Warning "Get-ApprovalState: '$approvalsPath' invalid, using defaults. $($_.Exception.Message)"
            Write-MachineHealthLog -LogPath $LogPath -Message "approvals_invalid $approvalsPath $($_.Exception.Message)"
            return (New-DefaultApprovalState)
        }
    }

    return (New-DefaultApprovalState)
}

function Test-ApprovalGranted {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [AllowNull()] $State,
        [Parameter(Mandatory = $true)] [string] $RemediationId
    )
    if ($null -eq $State -or $null -eq $State.remediations) { return $false }
    $entry = $State.remediations.PSObject.Properties[$RemediationId]
    if ($null -eq $entry) { return $false }
    return [bool]$entry.Value.approved
}

function Get-ServiceExclusion {
    # Service names from check_overrides.services.service_exclusions; @() when any
    # level of that path is absent, since StrictMode 3.0 throws on a missing property.
    [CmdletBinding()]
    [OutputType([string[]])]
    param([Parameter(Mandatory = $true)] [AllowNull()] $State)

    $node = $State
    foreach ($key in 'check_overrides', 'services', 'service_exclusions') {
        if ($null -eq $node) { return [string[]]@() }
        $prop = $node.PSObject.Properties[$key]
        if ($null -eq $prop) { return [string[]]@() }
        $node = $prop.Value
    }
    return [string[]]@($node | Where-Object { $_ })
}
