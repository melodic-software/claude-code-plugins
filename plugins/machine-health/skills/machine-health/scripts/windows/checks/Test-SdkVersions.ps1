#Requires -Version 7.4
<#
.SYNOPSIS
Check: .NET / Node / Python SDK versions vs EOL table. Emits a CheckResult JSON on stdout.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'sdk-versions'
$category = 'updates'
$commands = @(
    'dotnet --list-sdks'
    'node --version'
    'python --version'
)

function Get-MajorMinor {
    param([string] $VersionString)
    if ($VersionString -match '(\d+)\.(\d+)') {
        return "$($Matches[1]).$($Matches[2])"
    }
    return $null
}

function Get-MajorOnly {
    param([string] $VersionString)
    if ($VersionString -match 'v?(\d+)') { return $Matches[1] }
    return $null
}

function Get-SdkState {
    param($EolDate, $Now)
    if ($null -eq $EolDate) { return 'unknown_eol' }
    if ($EolDate -lt $Now) { return 'eol' }
    if (($EolDate - $Now).TotalDays -le 90) { return 'eol_soon' }
    return 'active'
}

function Add-SdkFinding {
    param(
        [Parameter(Mandatory)] [System.Collections.Generic.List[pscustomobject]] $Findings,
        [Parameter(Mandatory)] [string] $Runtime,
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [datetime] $Now,
        $EolBlock
    )
    $eolDate = $null
    if ($EolBlock -and $EolBlock.eol.PSObject.Properties[$Version]) {
        $eolDate = [datetime]::Parse($EolBlock.eol.$Version)
    }
    $state = Get-SdkState -EolDate $eolDate -Now $Now
    $Findings.Add([pscustomobject]@{
            runtime  = $Runtime
            version  = $Version
            eol_date = $eolDate ? $eolDate.ToString('yyyy-MM-dd') : $null
            state    = $state
        })
}

try {
    $skillRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
    $eolPath = Join-Path $skillRoot 'references\shared\sdk-eol-table.json'
    $eol = @{}
    if (Test-Path -LiteralPath $eolPath) {
        $raw = Get-Content -LiteralPath $eolPath -Raw | ConvertFrom-Json
        $eol = @{
            dotnet = $raw.dotnet
            node   = $raw.node
            python = $raw.python
        }
    }

    $now = Get-Date
    $findings = [System.Collections.Generic.List[pscustomobject]]::new()

    # .NET
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        try {
            $sdks = @(& dotnet --list-sdks 2>$null) -split "`r?`n" | Where-Object { $_ }
            $majors = @($sdks | ForEach-Object { Get-MajorMinor $_ } | Sort-Object -Unique)
            foreach ($m in $majors) {
                Add-SdkFinding -Findings $findings -Runtime 'dotnet' -Version $m -Now $now -EolBlock $eol.dotnet
            }
        } catch {
            Write-Verbose "Test-SdkVersions: dotnet enum failed. $($_.Exception.Message)"
        }
    }

    # Node
    if (Get-Command node -ErrorAction SilentlyContinue) {
        try {
            $nodeVer = (& node --version 2>$null).Trim()
            $major = Get-MajorOnly $nodeVer
            if ($major) {
                Add-SdkFinding -Findings $findings -Runtime 'node' -Version $major -Now $now -EolBlock $eol.node
            }
        } catch {
            Write-Verbose "Test-SdkVersions: node enum failed. $($_.Exception.Message)"
        }
    }

    # Python
    $pyCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
    if ($pyCmd) {
        try {
            $pyVer = (& $pyCmd.Source --version 2>&1) -replace 'Python\s+', ''
            $mm = Get-MajorMinor $pyVer
            if ($mm) {
                Add-SdkFinding -Findings $findings -Runtime 'python' -Version $mm -Now $now -EolBlock $eol.python
            }
        } catch {
            Write-Verbose "Test-SdkVersions: python enum failed. $($_.Exception.Message)"
        }
    }

    $crit = @($findings | Where-Object { $_.state -eq 'eol' })
    $warn = @($findings | Where-Object { $_.state -eq 'eol_soon' })

    $severity = 'OK'
    $summary = "$($findings.Count) SDK(s) detected, all active."
    if ($crit.Count -gt 0) {
        $severity = 'CRIT'
        $summary = "$($crit.Count) SDK(s) past EOL."
    } elseif ($warn.Count -gt 0) {
        $severity = 'WARN'
        $summary = "$($warn.Count) SDK(s) reach EOL within 90 days."
    } elseif ($findings.Count -gt 0) {
        $severity = 'INFO'
        $summary = "$($findings.Count) SDK(s) detected; oldest: $($findings[0].runtime) $($findings[0].version)."
    }

    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity $severity -Summary $summary -Commands $commands `
        -Detail @{
        runtimes_detected = $findings.Count
        runtimes          = @($findings)
        eol_count         = $crit.Count
        eol_soon_count    = $warn.Count
    } `
        -NeedsAdmin $false -RanSuccessfully $true `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'SDK version check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
