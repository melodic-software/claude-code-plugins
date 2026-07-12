#Requires -Version 7.4

<#
.SYNOPSIS
Load the per-user ApprovalState from $OutputBase/state/approvals.json.
First-run migrates checked boxes from the legacy skill-local TODO.md and
persists the result. Subsequent runs read approvals.json directly.

.DESCRIPTION
Fail-safe posture: any error (missing file, permission denied, malformed
JSON, schema violation) logs a warning and returns defaults (nothing
approved). A single broken approvals.json must not prevent the rest of
the audit from running.

Known remediation ids recognized for TODO.md -> approvals.json migration:

    clear-temp-files         <- matched on 'Clear-TempFiles' near [x]
    restart-stopped-service  <- matched on 'Restart-StoppedService' near [x]

Migration is one-shot: it triggers only when approvals.json is missing.
After migration, TODO.md checkboxes are ignored permanently.
#>

. (Join-Path $PSScriptRoot 'Assert-ApprovalState.ps1')
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

function Read-ApprovalsFromTodo {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $TodoPath
    )

    if (-not (Test-Path -LiteralPath $TodoPath)) { return $null }

    $migrations = [ordered]@{}
    try {
        $lines = Get-Content -LiteralPath $TodoPath -ErrorAction Stop
    } catch {
        Write-Verbose "Read-ApprovalsFromTodo: unable to read TODO.md. $($_.Exception.Message)"
        return $null
    }

    foreach ($line in $lines) {
        if ($line -notmatch '\[x\]') { continue }
        if ($line -match 'Restart-StoppedService|restart-stopped-service') {
            $migrations['restart-stopped-service'] = $true
        }
        if ($line -match 'Clear-TempFiles|clear-temp-files') {
            $migrations['clear-temp-files'] = $true
        }
    }

    if ($migrations.Count -eq 0) { return $null }

    $stamp = (Get-Date).ToString('o')
    $approvedBy = "$env:COMPUTERNAME\\$env:USERNAME"
    $rem = [ordered]@{}
    foreach ($id in $migrations.Keys) {
        $rem[$id] = [pscustomobject]@{
            approved    = $true
            approved_at = $stamp
            approved_by = $approvedBy
            notes       = 'Migrated from TODO.md'
        }
    }

    $sha = $null
    try {
        $hashParams = @{ LiteralPath = $TodoPath; Algorithm = 'SHA256'; ErrorAction = 'Stop' }
        $sha = (Get-FileHash @hashParams).Hash
    } catch {
        Write-Verbose "Read-ApprovalsFromTodo: unable to hash TODO.md. $($_.Exception.Message)"
    }

    return [pscustomobject]@{
        schema_version = '1.0'
        remediations   = [pscustomobject]$rem
        migration      = [pscustomobject]@{
            migrated_from_todo_md = $true
            migrated_at           = $stamp
            source_checksum       = $sha
        }
    }
}

function Get-ApprovalState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $StateDir,
        [string] $TodoPath,
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
            $raw = Get-Content -LiteralPath $approvalsPath -Raw -ErrorAction Stop
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

    if ($TodoPath) {
        $migrated = Read-ApprovalsFromTodo -TodoPath $TodoPath
        if ($null -ne $migrated) {
            try {
                $migrated | ConvertTo-Json -Depth 10 |
                    Set-Content -LiteralPath $approvalsPath -Encoding utf8 -ErrorAction Stop
                Write-MachineHealthLog -LogPath $LogPath `
                    -Message "approvals_migrated source=$TodoPath dest=$approvalsPath"
            } catch {
                Write-Warning "Get-ApprovalState: migration write failed. $($_.Exception.Message)"
                Write-MachineHealthLog -LogPath $LogPath `
                    -Message "approvals_migration_write_failed $($_.Exception.Message)"
            }
            return $migrated
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
