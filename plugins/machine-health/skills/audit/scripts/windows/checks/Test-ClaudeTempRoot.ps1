#Requires -Version 7.4
<#
.SYNOPSIS
Check: Claude Code temp-root footprint. Emits a CheckResult JSON on stdout.

See references/windows/check-catalog.md#17-claude-code-temp-root for rubric.
#>
[CmdletBinding()]
param([switch]$Human)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

# Walk budget. The orchestrator kills a check at 90s and check-result.schema.json
# caps duration_ms at 90000, so an unbounded walk of a multi-gigabyte tree does not
# merely time out -- it emits a schema-invalid result. Stop at 60s, keep the partial
# figures, and report UNKNOWN per the rubric's timeout row.
$budgetSeconds = 60

function Resolve-ClaudeTempRoot {
    <#
    .SYNOPSIS
    Returns the Claude Code temp root plus how it was resolved.

    .DESCRIPTION
    Candidates in precedence order; the first that exists wins. When none exists
    the first candidate is returned as the expected root so the caller can report
    "not present" against a concrete path.

    Every candidate ends in the literal `claude` segment. Claude Code appends
    `claude` on Windows to whatever temp base it resolves, so the base itself is
    never a candidate: a base with no `claude` child means Claude Code has not
    written there, and measuring the bare base would report an unrelated temp
    directory's size as this check's finding. The winning candidate is recorded
    in detail.root_source.

    Bases, in the order the documented default resolution implies:
    CLAUDE_CODE_TMPDIR when set, then the system temp directory (%TEMP%), then
    %LOCALAPPDATA%\Temp as the derivation of last resort when %TEMP% is unset.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $candidates = [System.Collections.Generic.List[pscustomobject]]::new()
    if (-not [string]::IsNullOrWhiteSpace($env:CLAUDE_CODE_TMPDIR)) {
        $candidates.Add([pscustomobject]@{
                Path   = (Join-Path $env:CLAUDE_CODE_TMPDIR 'claude')
                Source = 'CLAUDE_CODE_TMPDIR/claude'
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TEMP)) {
        $candidates.Add([pscustomobject]@{
                Path   = (Join-Path $env:TEMP 'claude')
                Source = 'TEMP/claude'
            })
    }
    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidates.Add([pscustomobject]@{
                Path   = (Join-Path $env:LOCALAPPDATA 'Temp\claude')
                Source = 'LOCALAPPDATA/Temp/claude'
            })
    }

    foreach ($c in $candidates) {
        $item = Get-Item -LiteralPath $c.Path -Force -ErrorAction SilentlyContinue
        if ($item -is [System.IO.DirectoryInfo]) {
            # FullName over the raw candidate: %TEMP% commonly carries an 8.3 short
            # name (KYLESE~1), which a human cannot match against what Explorer shows
            # and which compares unequal to the long form.
            return [pscustomobject]@{ Path = $item.FullName; Source = $c.Source; Exists = $true }
        }
    }

    if ($candidates.Count -eq 0) {
        return [pscustomobject]@{ Path = $null; Source = 'unresolved'; Exists = $false }
    }
    return [pscustomobject]@{ Path = $candidates[0].Path; Source = $candidates[0].Source; Exists = $false }
}

function Measure-SessionTree {
    <#
    .SYNOPSIS
    Accumulates size and file count under one session directory, yielding as soon
    as the shared walk budget is spent.

    .DESCRIPTION
    An explicit queue rather than `Get-ChildItem -Recurse`. The recursive form
    blocks until the whole subtree is enumerated, so the budget could only be
    tested after it returned -- and a single session directory holding tens of
    thousands of files can outlast the budget on its own, reaching the
    orchestrator's 90s kill. That kill emits nothing at all, losing even the
    partial figures the budget exists to preserve. Here the budget is tested per
    directory and per entry, so the walk always yields in time to report.

    Reparse points are skipped rather than followed. `Get-ChildItem -Recurse`
    does not follow them absent -FollowSymlink, so skipping preserves the
    behavior this replaces; a junction under the temp root would otherwise let
    the walk wander outside the tree or cycle forever.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [System.Diagnostics.Stopwatch] $Stopwatch,
        [Parameter(Mandatory = $true)] [int] $BudgetSeconds
    )

    $bytes = [long]0
    $files = 0
    $unreadable = 0
    $truncated = $false

    $pending = [System.Collections.Generic.Queue[string]]::new()
    $pending.Enqueue($Path)

    while ($pending.Count -gt 0) {
        if ($Stopwatch.Elapsed.TotalSeconds -ge $BudgetSeconds) { $truncated = $true; break }

        $entryErrors = @()
        $entries = @(Get-ChildItem -LiteralPath $pending.Dequeue() -Force `
                -ErrorAction SilentlyContinue -ErrorVariable entryErrors)
        $unreadable += $entryErrors.Count

        foreach ($e in $entries) {
            if ($Stopwatch.Elapsed.TotalSeconds -ge $BudgetSeconds) { $truncated = $true; break }
            if ($e.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
            if ($e.PSIsContainer) { $pending.Enqueue($e.FullName) }
            else {
                $bytes += $e.Length
                $files++
            }
        }
        if ($truncated) { break }
    }

    return [pscustomobject]@{
        Bytes           = $bytes
        FileCount       = $files
        UnreadableCount = $unreadable
        Truncated       = $truncated
    }
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$id = 'claude-temp-root'
$category = 'storage'
$commands = @(
    '$root = if ($env:CLAUDE_CODE_TMPDIR) { Join-Path $env:CLAUDE_CODE_TMPDIR ''claude'' } else { Join-Path $env:TEMP ''claude'' }'
    'Get-ChildItem -LiteralPath $root -Recurse -File -Force | Measure-Object -Property Length -Sum'
    'Get-ChildItem -LiteralPath $root -Directory -Force | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Force } | Measure-Object'
)

try {
    $root = Resolve-ClaudeTempRoot

    if (-not $root.Exists) {
        # Not applicable exits quietly and successfully (docs/PLUGIN-PHILOSOPHY.md
        # "Prerequisites and failure behavior"). Same shape as the battery check on a
        # desktop: OK with a negative detail flag, never UNKNOWN.
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'OK' -Summary 'Claude Code temp root not present.' -Commands $commands `
            -Detail @{
            root_path              = $root.Path
            root_source            = $root.Source
            root_exists            = $false
            total_bytes            = 0
            total_gb               = [double]0
            file_count             = 0
            session_dir_count      = 0
            project_key_count      = 0
            largest_session_gb     = [double]0
            oldest_session_age_days = 0
            unreadable_dir_count   = 0
            scan_truncated         = $false
            remediation_route      = 'disk-hygiene:clean'
        } `
            -NeedsAdmin $false -RanSuccessfully $true `
            -DurationMs ([int]$sw.ElapsedMilliseconds)
    } else {
        $now = Get-Date
        $totalBytes = [long]0
        $fileCount = 0
        $sessionCount = 0
        $largestSessionBytes = [long]0
        $oldestAgeDays = 0
        $unreadable = 0
        $truncated = $false

        $projectErrors = @()
        $projectDirs = @(Get-ChildItem -LiteralPath $root.Path -Directory -Force `
                -ErrorAction SilentlyContinue -ErrorVariable projectErrors)
        $unreadable += $projectErrors.Count

        # Layout is <root>/<project-key>/<session-id>/... . Age is measured at the
        # session level: a project-key directory is reused across sessions, so its
        # creation time reports when the key was first seen, not how long the oldest
        # unreclaimed content has survived.
        foreach ($p in $projectDirs) {
            if ($sw.Elapsed.TotalSeconds -ge $budgetSeconds) { $truncated = $true; break }

            $sessionErrors = @()
            $sessionDirs = @(Get-ChildItem -LiteralPath $p.FullName -Directory -Force `
                    -ErrorAction SilentlyContinue -ErrorVariable sessionErrors)
            $unreadable += $sessionErrors.Count

            foreach ($s in $sessionDirs) {
                if ($sw.Elapsed.TotalSeconds -ge $budgetSeconds) { $truncated = $true; break }

                $sessionCount++
                $ageDays = [int][math]::Floor(($now - $s.CreationTime).TotalDays)
                if ($ageDays -gt $oldestAgeDays) { $oldestAgeDays = $ageDays }

                $measured = Measure-SessionTree -Path $s.FullName -Stopwatch $sw `
                    -BudgetSeconds $budgetSeconds
                $unreadable += $measured.UnreadableCount
                $totalBytes += $measured.Bytes
                $fileCount += $measured.FileCount
                if ($measured.Bytes -gt $largestSessionBytes) {
                    $largestSessionBytes = $measured.Bytes
                }
                if ($measured.Truncated) { $truncated = $true; break }
            }
            if ($truncated) { break }
        }

        $totalGb = [math]::Round($totalBytes / 1GB, 2)
        $largestGb = [math]::Round($largestSessionBytes / 1GB, 2)

        $detail = @{
            root_path               = $root.Path
            root_source             = $root.Source
            root_exists             = $true
            total_bytes             = $totalBytes
            total_gb                = $totalGb
            file_count              = $fileCount
            session_dir_count       = $sessionCount
            project_key_count       = $projectDirs.Count
            largest_session_gb      = $largestGb
            oldest_session_age_days = $oldestAgeDays
            unreadable_dir_count    = $unreadable
            scan_truncated          = $truncated
            remediation_route       = 'disk-hygiene:clean'
        }

        if ($truncated -or $unreadable -gt 0) {
            # Partial figures are an undercount by an unbounded amount, so they cannot
            # clear a threshold in either direction -- an inaccessible multi-gigabyte
            # session would otherwise read as OK. Both ways a walk comes back
            # incomplete take the rubric's timeout row: UNKNOWN, with the partial
            # detail still shipped so the human sees the floor.
            #
            # ran_successfully = false is also what keeps the run out of history's
            # checks_ran, and so keeps an undercounted total_gb from becoming a trend
            # baseline. Left in, the recovered difference on the next complete walk
            # reads as growth and upgrades that WARN to CRIT on nothing.
            $reason = if ($truncated) {
                "Walk budget of ${budgetSeconds}s exceeded after $sessionCount " +
                'session directories; figures are a partial undercount.'
            } else {
                "$unreadable path(s) could not be read; figures are a partial " +
                'undercount, so no threshold verdict is possible.'
            }
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'UNKNOWN' `
                -Summary ("Claude Code temp-root scan incomplete; measured at least $totalGb GB " +
                    "across $sessionCount session dirs.") `
                -Commands $commands -Detail $detail -NeedsAdmin $false `
                -RanSuccessfully $false `
                -ErrorMessage $reason `
                -DurationMs ([int]$sw.ElapsedMilliseconds)
        } else {
            # Severity ladder (most severe first). This check never emits CRIT: the
            # tree is reclaimable cache with no data-loss or security consequence, and
            # severity-rubric.md reserves CRIT for imminent-failure and security
            # conditions while directing ambiguity to the lower level. Sustained growth
            # still reaches CRIT through the orchestrator's trend upgrade.
            #   WARN -- >=5 GB accumulated, or nothing reclaimed for >=14 days
            #   INFO -- >=1 GB, still within a plausible working set
            #   OK   -- <1 GB
            # The age arm is independent of size on purpose: a small tree that never
            # loses its oldest entry is the unpruned-growth signal this check exists for.
            $severity = 'OK'
            if ($totalGb -ge 5 -or $oldestAgeDays -ge 14) {
                $severity = 'WARN'
            } elseif ($totalGb -ge 1) {
                $severity = 'INFO'
            }

            $summary = "Claude Code temp root $totalGb GB across $sessionCount session dirs " +
            "($fileCount files); oldest $oldestAgeDays d."
            if ($severity -eq 'WARN') {
                $summary += ' Route removal to disk-hygiene:clean.'
            }

            # Reached only on a complete walk, so every figure here is exact rather
            # than a lower bound and the threshold verdict stands on its own.
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity $severity -Summary $summary -Commands $commands -Detail $detail `
                -NeedsAdmin $false -RanSuccessfully $true `
                -DurationMs ([int]$sw.ElapsedMilliseconds)
        }
    }
} catch {
    $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
        -Severity 'UNKNOWN' -Summary 'Claude Code temp-root check failed.' -Commands $commands `
        -RanSuccessfully $false -ErrorMessage $_.Exception.Message `
        -DurationMs ([int]$sw.ElapsedMilliseconds)
}

$sw.Stop()
$result.duration_ms = [int]$sw.ElapsedMilliseconds
$result | Write-HealthResult -Human:$Human
