#Requires -Version 7.4
<#
.SYNOPSIS
Check: unexpected entries at fixed-volume roots. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#19-drive-root-litter for rubric.

.DESCRIPTION
Lists each fixed-volume root non-recursively and diffs it against the
expected-entry baseline in reference/windows/drive-root-baseline.jsonc.
The system drive gets the full baseline diff; a non-system volume root
legitimately holds arbitrary user content, so only known litter-name shapes
are reported there. Read-only: the check never deletes, moves, or modifies
anything it finds.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    # The overrides below exist for tests and manual scratch-tree runs; the
    # orchestrator dispatches argument-less (Get-CheckArgument default) and the
    # defaults resolve the real volumes and the shipped baseline.
    [string]$SystemRootPath,
    [string[]]$DataRootPath,
    [string]$BaselinePath
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')
. (Join-Path $PSScriptRoot '..\lib\ConvertFrom-Jsonc.ps1')

function Get-BaselineList {
    <#
    .SYNOPSIS
    Returns one pattern list from the parsed baseline, throwing a message that
    names the missing piece rather than letting StrictMode produce a generic
    property error.
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory = $true)] $Baseline,
        [Parameter(Mandatory = $true)] [string] $Section,
        [Parameter(Mandatory = $true)] [ValidateSet('directories', 'files')] [string] $Kind
    )
    $sectionProp = $Baseline.PSObject.Properties[$Section]
    if ($null -eq $sectionProp) { throw "Baseline has no '$Section' section." }
    $kindProp = $sectionProp.Value.PSObject.Properties[$Kind]
    if ($null -eq $kindProp) { throw "Baseline section '$Section' has no '$Kind' list." }
    return [string[]]@($kindProp.Value)
}

function Test-NameMatchesAny {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $Name,
        [AllowEmptyCollection()] [string[]] $Patterns
    )
    foreach ($p in $Patterns) {
        if ($Name -like $p) { return $true }
    }
    return $false
}

function Get-RootResidue {
    <#
    .SYNOPSIS
    Lists one volume root (non-recursive) and returns the entries the baseline
    does not account for.

    .DESCRIPTION
    Posture depends on the volume:
      - system:      report every entry not matching all_volumes + system_drive.
      - non-system:  report only entries matching data_volume_litter shapes;
                     everything else is presumed intentional user content.
    Owner and directory-emptiness are best-effort context: either can be
    unreadable without elevation, and a $null there never changes severity.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [bool] $IsSystem,
        [Parameter(Mandatory = $true)] $Baseline
    )

    $sharedDirs = Get-BaselineList -Baseline $Baseline -Section 'all_volumes' -Kind 'directories'
    $sharedFiles = Get-BaselineList -Baseline $Baseline -Section 'all_volumes' -Kind 'files'
    $systemDirs = Get-BaselineList -Baseline $Baseline -Section 'system_drive' -Kind 'directories'
    $systemFiles = Get-BaselineList -Baseline $Baseline -Section 'system_drive' -Kind 'files'
    $litterDirs = Get-BaselineList -Baseline $Baseline -Section 'data_volume_litter' -Kind 'directories'
    $litterFiles = Get-BaselineList -Baseline $Baseline -Section 'data_volume_litter' -Kind 'files'

    # -ErrorAction Stop: a root that cannot be listed at all must surface as a
    # failed scan, not as a clean one -- an empty listing reads as zero residue.
    $entries = @(Get-ChildItem -LiteralPath $Root -Force -ErrorAction Stop)

    $residue = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($e in $entries) {
        $isDir = [bool]$e.PSIsContainer
        if ($IsSystem) {
            $expected = if ($isDir) { @($sharedDirs) + @($systemDirs) } else { @($sharedFiles) + @($systemFiles) }
            if (Test-NameMatchesAny -Name $e.Name -Patterns $expected) { continue }
        } else {
            # Volume housekeeping ($Recycle.Bin etc.) appears on data volumes
            # too; it is expected there, not litter.
            $expected = if ($isDir) { $sharedDirs } else { $sharedFiles }
            if (Test-NameMatchesAny -Name $e.Name -Patterns $expected) { continue }
            $litter = if ($isDir) { $litterDirs } else { $litterFiles }
            if (-not (Test-NameMatchesAny -Name $e.Name -Patterns $litter)) { continue }
        }

        $owner = try { (Get-Acl -LiteralPath $e.FullName -ErrorAction Stop).Owner } catch { $null }
        $isEmpty = $null
        if ($isDir) {
            $isEmpty = try {
                # First entry only -- a stray directory can be arbitrarily large
                # and this check never recurses.
                $first = [System.IO.Directory]::EnumerateFileSystemEntries($e.FullName) |
                    Select-Object -First 1
                $null -eq $first
            } catch { $null }
        }

        $residue.Add([pscustomobject]@{
                volume     = $Root
                name       = $e.Name
                type       = $isDir ? 'directory' : 'file'
                size_bytes = $isDir ? $null : [long]$e.Length
                is_empty   = $isEmpty
                owner      = $owner
                # Date, not instant: stable across runs (identical output feeds
                # the catalog's identical_streak accounting) and day granularity
                # is all "how long has this dropping been here" needs.
                created    = $e.CreationTimeUtc.ToString('yyyy-MM-dd')
            })
    }

    return [pscustomobject]@{
        Root       = $Root
        Posture    = $IsSystem ? 'baseline' : 'litter-names'
        EntryCount = $entries.Count
        Residue    = $residue
    }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'drive-root-litter'
$category = 'storage'
$commands = @(
    "Get-ChildItem -LiteralPath `"`$env:SystemDrive\`" -Force | Select-Object Name, Mode, Length"
    "Get-Volume | Where-Object { `$_.DriveType -eq 'Fixed' -and `$_.DriveLetter }"
)

try {
    $skillRoot = Split-Path -Path $PSScriptRoot -Parent | Split-Path -Parent | Split-Path -Parent
    if (-not $BaselinePath) {
        $BaselinePath = Join-Path $skillRoot 'reference\windows\drive-root-baseline.jsonc'
    }
    # No baseline means no way to tell residue from a legitimate entry, so the
    # check cannot answer -- UNKNOWN, never a guess.
    $baseline = Get-Content -LiteralPath $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Jsonc

    $systemRoot = if ($SystemRootPath) { $SystemRootPath } else { "$env:SystemDrive\" }
    $dataRoots = if ($PSBoundParameters.ContainsKey('DataRootPath')) {
        @($DataRootPath)
    } else {
        # Fixed, lettered volumes only: removable media and network drives hold
        # user-managed content with no OS-imposed root layout to diff against.
        $systemLetter = $systemRoot.TrimEnd('\').TrimEnd(':')
        @(Get-Volume -ErrorAction SilentlyContinue |
                Where-Object { $_.DriveType -eq 'Fixed' -and $_.DriveLetter } |
                Where-Object { "$($_.DriveLetter)" -ne $systemLetter } |
                ForEach-Object { "$($_.DriveLetter):\" } |
                Sort-Object)
    }

    $volumes = [System.Collections.Generic.List[pscustomobject]]::new()
    $residue = [System.Collections.Generic.List[pscustomobject]]::new()
    $failedRoots = [System.Collections.Generic.List[string]]::new()

    # Trailing separator so detail.residue "volume + name" concatenations read
    # as real paths ("C:\tmp"), for drive roots and override paths alike.
    $normalize = { param($p) ($p.EndsWith('\') -or $p.EndsWith('/')) ? $p : "$p\" }
    $systemRoot = & $normalize $systemRoot
    $dataRoots = @($dataRoots | ForEach-Object { & $normalize $_ })

    $targets = @([pscustomobject]@{ Root = $systemRoot; IsSystem = $true })
    $targets += @($dataRoots | ForEach-Object { [pscustomobject]@{ Root = $_; IsSystem = $false } })

    foreach ($t in $targets) {
        try {
            $scan = Get-RootResidue -Root $t.Root -IsSystem $t.IsSystem -Baseline $baseline
            $volumes.Add([pscustomobject]@{
                    root          = $scan.Root
                    posture       = $scan.Posture
                    entry_count   = $scan.EntryCount
                    residue_count = $scan.Residue.Count
                })
            foreach ($r in $scan.Residue) { $residue.Add($r) }
        } catch {
            $failedRoots.Add("$($t.Root): $($_.Exception.Message)")
        }
    }

    # Deterministic order: identical machine state must produce identical
    # output run over run so the catalog's identical_streak accounting works.
    $residueSorted = @($residue | Sort-Object volume, name)

    $detail = @{
        baseline_path         = $BaselinePath
        system_root           = $systemRoot
        volumes               = @($volumes)
        residue               = $residueSorted
        residue_count         = $residueSorted.Count
        unreadable_root_count = $failedRoots.Count
        remediation_route     = 'disk-hygiene:clean'
    }

    if ($failedRoots.Count -gt 0) {
        # An unlistable root can hide any amount of litter, so a threshold
        # verdict on the volumes that did scan would overstate what is known.
        # Partial residue still ships so the human sees what was found.
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'UNKNOWN' `
            -Summary ("Drive-root scan incomplete: $($failedRoots.Count) root(s) could not be " +
                "listed; $($residueSorted.Count) unexpected entries found on the rest.") `
            -Commands $commands -Detail $detail -NeedsAdmin $false `
            -RanSuccessfully $false `
            -ErrorMessage ($failedRoots -join '; ') `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    } else {
        # Severity ladder (most severe first). This check never emits CRIT:
        # root litter is tidiness with no data-loss or security consequence,
        # and severity-rubric.md reserves CRIT for imminent-failure and
        # security conditions while directing ambiguity to the lower level.
        #   WARN -- >=10 residue entries: something is actively dumping at a root.
        #   INFO -- 1-9 residue entries.
        #   OK   -- none.
        $severity = 'OK'
        if ($residueSorted.Count -ge 10) {
            $severity = 'WARN'
        } elseif ($residueSorted.Count -ge 1) {
            $severity = 'INFO'
        }

        $summary = if ($residueSorted.Count -eq 0) {
            "Volume roots clean: $($volumes.Count) root(s) scanned, no unexpected entries."
        } else {
            # Full paths when they fit, bare names when they don't: the schema
            # caps summary at 240 chars and an override root can be arbitrarily
            # long. Deterministic either way; detail.residue always has the paths.
            $lead = "$($residueSorted.Count) unexpected " +
                "entr$($residueSorted.Count -eq 1 ? 'y' : 'ies') at volume roots"
            $tail = '. Route removal to disk-hygiene:clean.'
            $candidate = ''
            foreach ($render in @({ "$($args[0].volume)$($args[0].name)" }, { $args[0].name })) {
                $examples = @($residueSorted | Select-Object -First 3 |
                        ForEach-Object { & $render $_ }) -join ', '
                $candidate = "$lead ($examples)$tail"
                if ($candidate.Length -le 240) { break }
            }
            if ($candidate.Length -gt 240) { $candidate = "$lead$tail" }
            $candidate
        }

        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity $severity -Summary $summary -Commands $commands -Detail $detail `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Drive-root litter check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
