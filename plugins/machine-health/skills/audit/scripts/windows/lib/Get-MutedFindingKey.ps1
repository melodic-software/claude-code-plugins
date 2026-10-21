#Requires -Version 7.4

<#
.SYNOPSIS
Read the owner's finding mutes from <StateBase>/state/mutes.json and return the
muted FindingKeys for one check.

.DESCRIPTION
Get-MuteState is read only: it creates no directory or file, migrates nothing
and writes no log, so a run that must leave the state folder alone can still
call it. It opens the file with FileShare.ReadWrite | FileShare.Delete so a
writer replacing the file never blocks it.

Fail-safe posture: a missing, empty, malformed or schema-invalid file means no
mutes. A broken file warns and is left as it is; muted items then count toward
severity again until the file is fixed.

Schema: catalog/schemas/mutes.schema.json.
#>

function Get-MuteState {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $StateDir
    )

    $none = [pscustomobject]@{ schema_version = '1.0'; checks = [pscustomobject]@{} }
    $mutesPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
        (Join-Path $StateDir 'mutes.json'))
    if (-not [System.IO.File]::Exists($mutesPath)) { return $none }

    try {
        $stream = [System.IO.File]::Open($mutesPath, 'Open', 'Read', [System.IO.FileShare]'ReadWrite, Delete')
        try {
            $raw = [System.IO.StreamReader]::new($stream).ReadToEnd()
        } finally {
            $stream.Dispose()
        }
        if ([string]::IsNullOrWhiteSpace($raw)) { return $none }
        $schemaPath = Join-Path $PSScriptRoot '..\..\..\catalog\schemas\mutes.schema.json'
        if (-not (Test-Json -Json $raw -SchemaFile $schemaPath -ErrorAction Stop)) {
            throw 'does not match mutes.schema.json.'
        }
        return ($raw | ConvertFrom-Json -ErrorAction Stop)
    } catch {
        Write-Warning "Get-MuteState: '$mutesPath' unreadable or invalid, ignoring mutes. $($_.Exception.Message)"
        return $none
    }
}

function Get-MutedFindingKey {
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)] [AllowNull()] $State,
        [Parameter(Mandatory = $true)] [string] $CheckId
    )

    $check = if ($null -ne $State -and $null -ne $State.PSObject.Properties['checks']) {
        $State.checks.PSObject.Properties[$CheckId]
    }
    $keys = [string[]]@()
    if ($null -ne $check) { $keys = [string[]]@($check.Value.muted_findings | ForEach-Object { $_.key }) }
    # NoEnumerate keeps an empty or one-key result a string[] for the caller.
    Write-Output -NoEnumerate -InputObject $keys
}
