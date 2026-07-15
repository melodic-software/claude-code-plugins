#Requires -Version 7.4
<#
.SYNOPSIS
Check: Docker + WSL disk usage. Emits a CheckResult JSON on stdout.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

function ConvertFrom-HumanSize {
    param([string] $InputString)
    if (-not $InputString) { return $null }
    $s = $InputString.Trim()
    if ($s -match '^([\d\.]+)\s*(B|KB|MB|GB|TB)?$') {
        $n = [double]$Matches[1]
        $unit = $Matches[2]
        switch ($unit) {
            'KB' { return [long]($n * 1KB) }
            'MB' { return [long]($n * 1MB) }
            'GB' { return [long]($n * 1GB) }
            'TB' { return [long]($n * 1TB) }
            default { return [long]$n }
        }
    }
    return $null
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'container-disk-usage'
$category = 'storage'
$commands = @(
    'docker system df --format json'
    'wsl --list --verbose'
)

try {
    $dockerBytes = $null
    $wslBytes = $null
    $notes = [System.Collections.Generic.List[string]]::new()

    # Docker.
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        try {
            $raw = docker system df --format '{{json .}}' 2>&1
            if ($LASTEXITCODE -eq 0 -and $raw) {
                $total = 0
                foreach ($line in ($raw -split "`r?`n")) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    try {
                        $row = $line | ConvertFrom-Json -ErrorAction Stop
                        if ($row.PSObject.Properties['Size']) {
                            # Size field is a human string like "12.3GB". Parse loosely.
                            $bytes = ConvertFrom-HumanSize -InputString $row.Size
                            if ($bytes) { $total += $bytes }
                        }
                    } catch {
                        Write-Verbose "Docker df parse failed: $($_.Exception.Message)"
                    }
                }
                $dockerBytes = $total
            }
        } catch {
            $notes.Add("docker system df failed: $($_.Exception.Message)")
        }
    }

    # WSL distros.
    if (Get-Command wsl -ErrorAction SilentlyContinue) {
        try {
            # Probe wsl availability; output is unused, only the failure path matters.
            $null = & wsl --list --verbose 2>&1
        } catch {
            $notes.Add("wsl enum failed: $($_.Exception.Message)")
        }

        # Per-distro vhdx size (best effort): LocalState\ext4.vhdx per package.
        $packagesRoot = "$env:LOCALAPPDATA\Packages"
        if (Test-Path -LiteralPath $packagesRoot) {
            $vhdxTotal = 0
            try {
                $vhdxFiles = @(Get-ChildItem -Path $packagesRoot -Filter 'ext4.vhdx' `
                        -Recurse -Depth 3 -ErrorAction SilentlyContinue)
                foreach ($v in $vhdxFiles) { $vhdxTotal += $v.Length }
                $wslBytes = $vhdxTotal
            } catch {
                Write-Verbose "WSL vhdx scan failed: $($_.Exception.Message)"
            }
        }
    }

    $dockerGb = $null -ne $dockerBytes ? [math]::Round($dockerBytes / 1GB, 1) : $null
    $wslGb = $null -ne $wslBytes ? [math]::Round($wslBytes / 1GB, 1) : $null

    $severity = 'OK'
    $summary = 'No container disk signals.'
    if ($null -ne $dockerGb -or $null -ne $wslGb) {
        $severity = 'INFO'
        $parts = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $dockerGb) { $parts.Add("Docker $dockerGb GB") }
        if ($null -ne $wslGb) { $parts.Add("WSL $wslGb GB") }
        $summary = ($parts -join ', ') + '.'
    }
    if (($null -ne $dockerGb -and $dockerGb -gt 50) -or ($null -ne $wslGb -and $wslGb -gt 30)) {
        $severity = 'WARN'
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands `
        -Detail @{
        docker_bytes  = $dockerBytes
        wsl_bytes     = $wslBytes
        docker_gb     = $dockerGb
        wsl_gb        = $wslGb
    } `
        -NeedsAdmin $false -RanSuccessfully $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds) `
        -Notes ($notes.Count -gt 0 ? ($notes -join '; ') : $null)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Container disk check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
