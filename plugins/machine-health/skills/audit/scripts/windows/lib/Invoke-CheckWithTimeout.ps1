#Requires -Version 7.4

<#
.SYNOPSIS
Run one check script in a Start-Job under a timeout and parse its JSON output.

.DESCRIPTION
Returns a hashtable: ok = $true with the parsed result, or ok = $false with a
reason of timeout, no_output or invalid_json. elapsed_ms is set either way.
#>

function Invoke-CheckWithTimeout {
    [CmdletBinding()]
    [OutputType([hashtable])]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseUsingScopeModifierInNewRunspaces', '',
        Justification = 'Parameter passed via -ArgumentList is bound via param block.')]
    param(
        [Parameter(Mandatory = $true)] [string] $ScriptPath,
        [int] $TimeoutSec = 90,
        [hashtable] $Arguments = @{}
    )
    $jobSw = [System.Diagnostics.Stopwatch]::StartNew()
    # Splat per-check arguments across the job boundary. -ArgumentList serializes
    # the hashtable; @ArgMap binds it to the check's named params. An empty map
    # (the common case) runs the check argument-less. The job's pwsh puts the user module
    # folder back on PSModulePath at startup, so it takes this process's value instead and
    # an elevated pass's pinned path holds in the check too.
    $job = Start-Job -ScriptBlock {
        param($ScriptToRun, $ArgMap, $ModulePath)
        $env:PSModulePath = $ModulePath
        & $ScriptToRun @ArgMap
    } -ArgumentList $ScriptPath, $Arguments, $env:PSModulePath
    $completed = Wait-Job -Job $job -Timeout $TimeoutSec
    $jobSw.Stop()
    if (-not $completed) {
        Stop-Job -Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
        return @{ ok = $false; reason = 'timeout'; elapsed_ms = [int]$jobSw.ElapsedMilliseconds }
    }
    $outputLines = Receive-Job -Job $job -ErrorAction SilentlyContinue
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue | Out-Null
    $joined = ($outputLines | Where-Object { $_ }) -join "`n"
    if ([string]::IsNullOrWhiteSpace($joined)) {
        return @{ ok = $false; reason = 'no_output'; elapsed_ms = [int]$jobSw.ElapsedMilliseconds }
    }
    try {
        $parsed = $joined | ConvertFrom-Json -ErrorAction Stop
        return @{ ok = $true; result = $parsed; elapsed_ms = [int]$jobSw.ElapsedMilliseconds }
    } catch {
        return @{
            ok         = $false
            reason     = 'invalid_json'
            raw_output = $joined
            error      = $_.Exception.Message
            elapsed_ms = [int]$jobSw.ElapsedMilliseconds
        }
    }
}
