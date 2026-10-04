#Requires -Version 7.4
<#
.SYNOPSIS
Check: Claude Code temp-root footprint. Emits a CheckResult JSON on stdout.

See reference/windows/check-catalog.md#17-claude-code-temp-root for rubric.
#>
[CmdletBinding()]
param(
    [switch]$Human,
    # The overrides below exist for tests and manual scratch-tree runs; the
    # orchestrator dispatches argument-less (Get-CheckArgument default) and the
    # defaults are the rubric's figures.
    [long]$TaskOutputWarnBytes = 1GB,
    [int]$BudgetSeconds = 60,
    [int]$TaskOutputBudgetSeconds = 20
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot '..\lib\Write-HealthResult.ps1')

# Walk budget. The orchestrator kills a check at 90s and check-result.schema.json
# caps duration_ms at 90000, so an unbounded walk of a multi-gigabyte tree does not
# merely time out -- it emits a schema-invalid result. Stop at 60s, keep the partial
# figures, and report UNKNOWN per the rubric's timeout row.
$budgetSeconds = $BudgetSeconds

# The task-output listing runs first on the same clock and stops at its own cap,
# so a tree too large to walk still gets its largest files named and the walk
# keeps the rest of the budget.
$taskOutputBudgetSeconds = $TaskOutputBudgetSeconds
$taskOutputTopCount = 5

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

    # Precedence order is the order of this table; a base whose environment
    # variable is unset or blank contributes no candidate.
    $bases = @(
        @{ Base = $env:CLAUDE_CODE_TMPDIR; Child = 'claude'; Source = 'CLAUDE_CODE_TMPDIR/claude' }
        @{ Base = $env:TEMP; Child = 'claude'; Source = 'TEMP/claude' }
        @{ Base = $env:LOCALAPPDATA; Child = 'Temp\claude'; Source = 'LOCALAPPDATA/Temp/claude' }
    )

    $candidates = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($b in $bases) {
        if ([string]::IsNullOrWhiteSpace($b.Base)) { continue }
        $candidates.Add([pscustomobject]@{
                Path   = (Join-Path $b.Base $b.Child)
                Source = $b.Source
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

function Find-LargestTaskOutput {
    <#
    .SYNOPSIS
    Lists `<root>/<project-key>/<session-id>/tasks/*.output` by size, largest
    first, from directory listings alone.

    .DESCRIPTION
    Exactly three levels are listed, never a recursive walk, so the cost scales
    with the number of sessions rather than the number of files under them. Only
    file metadata is read: task output can hold secrets, so its contents are
    never opened. Reparse points are skipped for the same reason the walk skips
    them.

    Every level is streamed from the .NET enumerators and the budget is tested
    per entry. `Get-ChildItem` hands back a directory only once all of it is
    listed, so one tasks directory with millions of entries, or on a slow share,
    would hold the listing past its cap and toward the orchestrator's 90s kill.
    Only the Top largest are kept; Count and OverCount cover every match seen.

    Stopwatch is read only through .Elapsed, so a test can pass a stand-in clock.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [object] $Stopwatch,
        [Parameter(Mandatory = $true)] [int] $BudgetSeconds,
        [Parameter(Mandatory = $true)] [int] $Top,
        [Parameter(Mandatory = $true)] [long] $WarnBytes
    )

    $reparse = [System.IO.FileAttributes]::ReparsePoint
    # Only reparse points are skipped: the default also skips Hidden and System
    # entries, which -Force listed. IgnoreInaccessible keeps its default of true,
    # because the walk counts unreadable paths itself.
    $options = [System.IO.EnumerationOptions]::new()
    $options.AttributesToSkip = $reparse

    $largest = [System.Collections.Generic.List[pscustomobject]]::new()
    $count = 0
    $overCount = 0
    $truncated = $false

    :listing foreach ($p in [System.IO.DirectoryInfo]::new($Root).EnumerateDirectories('*', $options)) {
        if ($Stopwatch.Elapsed.TotalSeconds -ge $BudgetSeconds) { $truncated = $true; break }
        try {
            foreach ($s in $p.EnumerateDirectories('*', $options)) {
                if ($Stopwatch.Elapsed.TotalSeconds -ge $BudgetSeconds) { $truncated = $true; break listing }

                $tasksDir = [System.IO.DirectoryInfo]::new([System.IO.Path]::Join($s.FullName, 'tasks'))
                if (-not $tasksDir.Exists -or ($tasksDir.Attributes -band $reparse)) { continue }
                try {
                    foreach ($f in $tasksDir.EnumerateFiles('*.output', $options)) {
                        if ($Stopwatch.Elapsed.TotalSeconds -ge $BudgetSeconds) { $truncated = $true; break listing }
                        if ($f.Extension -ne '.output') { continue }

                        $count++
                        if ($f.Length -ge $WarnBytes) { $overCount++ }
                        if ($largest.Count -ge $Top -and $f.Length -le $largest[$largest.Count - 1].bytes) { continue }
                        $at = 0
                        while ($at -lt $largest.Count -and $largest[$at].bytes -ge $f.Length) { $at++ }
                        $largest.Insert($at, [pscustomobject]@{
                                path           = $f.FullName
                                bytes          = [long]$f.Length
                                gb             = [math]::Round($f.Length / 1GB, 2)
                                last_write_utc = $f.LastWriteTimeUtc.ToString('o')
                                session_dir    = $s.FullName
                            })
                        if ($largest.Count -gt $Top) { $largest.RemoveAt($Top) }
                    }
                } catch [System.IO.IOException] {
                    # A session removed mid-listing takes its outputs with it.
                    continue
                }
            }
        } catch [System.IO.IOException] {
            continue
        }
    }

    return [pscustomobject]@{
        Count     = $count
        OverCount = $overCount
        Largest   = @($largest)
        Truncated = $truncated
    }
}

function Format-TaskOutputFinding {
    <#
    .SYNOPSIS
    Sentence naming the largest task output at or above the threshold, or $null
    when none is.

    .DESCRIPTION
    The schema caps the summary at 240 characters and a real task-output path
    can approach that alone, so the file is named by the longest form that fits
    in MaxLength: the full path, then the path under the root, then the file
    name. The full path is always in detail.largest_task_outputs.

    OverCount comes from the listing, not from Largest: Largest keeps only the
    top few, so counting it would cap the "more" figure.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)] [AllowEmptyCollection()] [object[]] $Largest,
        [Parameter(Mandatory = $true)] [int] $OverCount,
        [Parameter(Mandatory = $true)] [string] $Root,
        [Parameter(Mandatory = $true)] [int] $MaxLength
    )

    if ($OverCount -eq 0 -or $Largest.Count -eq 0) { return $null }
    $top = $Largest[0]
    $names = @(
        $top.path
        [System.IO.Path]::GetRelativePath($Root, $top.path)
        [System.IO.Path]::GetFileName($top.path)
    )
    $more = if ($OverCount -gt 1) { "; $($OverCount - 1) more over the threshold" } else { '' }
    foreach ($name in $names) {
        $text = "Task output $name is $($top.gb) GB, last write " +
        "$($top.last_write_utc.Substring(0, 10))$more."
        if ($text.Length -le $MaxLength) { return $text }
    }
    return "Task output of $($top.gb) GB in detail.largest_task_outputs."
}

$id = 'claude-temp-root'
$category = 'storage'
$commands = @(
    '$root = if ($env:CLAUDE_CODE_TMPDIR) { Join-Path $env:CLAUDE_CODE_TMPDIR ''claude'' } else { Join-Path $env:TEMP ''claude'' }'
    'Get-ChildItem -LiteralPath $root -Recurse -File -Force | Measure-Object -Property Length -Sum'
    'Get-ChildItem -LiteralPath $root -Directory -Force | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Directory -Force } | Measure-Object'
    'Get-ChildItem -Path (Join-Path $root ''*\*\tasks\*.output'') -File -Force | Sort-Object Length -Descending | Select-Object -First 5 FullName, Length, LastWriteTimeUtc'
)

$FailureSummary = 'Claude Code temp-root check failed.'
$PassThru = $false
$CheckBody = {
    $root = Resolve-ClaudeTempRoot

    if (-not $root.Exists) {
        # Not applicable exits quietly and successfully (docs/plugin-philosophy.md
        # "Prerequisites and failure behavior"). Same shape as the battery check on a
        # desktop: OK with a negative detail flag, never UNKNOWN.
        $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
            -Severity 'OK' -Summary 'Claude Code temp root not present.' -Commands $commands `
            -Detail @{
            root_path               = $root.Path
            root_source             = $root.Source
            root_exists             = $false
            total_bytes             = 0
            total_gb                = [double]0
            file_count              = 0
            session_dir_count       = 0
            project_key_count       = 0
            largest_session_gb      = [double]0
            oldest_session_age_days = 0
            unreadable_dir_count    = 0
            scan_truncated          = $false
            task_output_count       = 0
            task_output_over_count  = 0
            largest_task_outputs    = @()
            largest_task_output_gb  = [double]0
            task_output_truncated   = $false
            remediation_route       = 'disk-hygiene:clean'
        } `
            -NeedsAdmin $false -RanSuccessfully $true
    } else {
        $now = Get-Date

        $taskOutputs = Find-LargestTaskOutput -Root $root.Path -Stopwatch $sw `
            -BudgetSeconds $taskOutputBudgetSeconds -Top $taskOutputTopCount -WarnBytes $TaskOutputWarnBytes
        $largestTaskOutputs = @($taskOutputs.Largest)
        $largestTaskBytes = if ($largestTaskOutputs.Count -gt 0) { $largestTaskOutputs[0].bytes } else { [long]0 }
        $taskOutputOver = $taskOutputs.OverCount -gt 0
        $summaryCap = 240

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
            task_output_count       = $taskOutputs.Count
            task_output_over_count  = $taskOutputs.OverCount
            largest_task_outputs    = $largestTaskOutputs
            largest_task_output_gb  = [math]::Round($largestTaskBytes / 1GB, 2)
            task_output_truncated   = $taskOutputs.Truncated
            remediation_route       = 'disk-hygiene:clean'
        }

        if ($truncated -or $unreadable -gt 0 -or $taskOutputs.Truncated) {
            # Partial figures are an undercount by an unbounded amount, so they cannot
            # clear a threshold in either direction -- an inaccessible multi-gigabyte
            # session would otherwise read as OK. Both ways a walk comes back
            # incomplete take the rubric's timeout row: UNKNOWN, with the partial
            # detail still shipped so the human sees the floor.
            #
            # A cut-off task-output listing is the same kind of floor for the per-file
            # arm: a completed walk proves the totals, not that no output reached the
            # threshold, so it takes the same row.
            #
            # ran_successfully = false is also what keeps the run out of history's
            # checks_ran, and so keeps an undercounted total_gb from becoming a trend
            # baseline. Left in, the recovered difference on the next complete walk
            # reads as growth and upgrades that WARN to CRIT on nothing.
            #
            # The schema pins a failed run to UNKNOWN, so an oversized task output
            # cannot lift this verdict to WARN; it is named in the summary instead,
            # which is what the human reads when the walk could not finish.
            $reason = if ($truncated) {
                "Walk budget of ${budgetSeconds}s exceeded after $sessionCount " +
                'session directories; figures are a partial undercount.'
            } elseif ($unreadable -gt 0) {
                "$unreadable path(s) could not be read; figures are a partial " +
                'undercount, so no threshold verdict is possible.'
            } else {
                "Task-output listing budget of ${taskOutputBudgetSeconds}s exceeded after " +
                "$($taskOutputs.Count) outputs; no per-file verdict is possible."
            }
            $summary = "Claude Code temp-root scan incomplete; measured at least $totalGb GB " +
            "across $sessionCount session dirs."
            $tail = if ($taskOutputs.Truncated) {
                ' Task-output listing partial.'
            } elseif ($taskOutputOver) {
                ' Task-output listing complete.'
            } else { '' }
            if ($taskOutputOver) {
                $finding = Format-TaskOutputFinding -Largest $largestTaskOutputs `
                    -OverCount $taskOutputs.OverCount -Root $root.Path `
                    -MaxLength ($summaryCap - $summary.Length - $tail.Length - 1)
                $summary += " $finding"
            }
            $summary += $tail
            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity 'UNKNOWN' -Summary $summary `
                -Commands $commands -Detail $detail -NeedsAdmin $false `
                -RanSuccessfully $false `
                -ErrorMessage $reason
        } else {
            # Severity ladder (most severe first). This check never emits CRIT: the
            # tree is reclaimable cache with no data-loss or security consequence, and
            # severity-rubric.md reserves CRIT for imminent-failure and security
            # conditions while directing ambiguity to the lower level. Sustained growth
            # still reaches CRIT through the orchestrator's trend upgrade.
            #   WARN -- >=5 GB accumulated, nothing reclaimed for >=14 days, or one
            #           background-task output file >=1 GB
            #   INFO -- >=1 GB, still within a plausible working set
            #   OK   -- <1 GB
            # The age arm is independent of size on purpose: a small tree that never
            # loses its oldest entry is the unpruned-growth signal this check exists for.
            # The per-file arm is independent too: one runaway task output is the
            # file to remove, and a total-size verdict alone never names it.
            $severity = 'OK'
            if ($totalGb -ge 5 -or $oldestAgeDays -ge 14 -or $taskOutputOver) {
                $severity = 'WARN'
            } elseif ($totalGb -ge 1) {
                $severity = 'INFO'
            }

            $summary = "Claude Code temp root $totalGb GB across $sessionCount session dirs " +
            "($fileCount files); oldest $oldestAgeDays d."
            $tail = if ($severity -eq 'WARN') { ' Route removal to disk-hygiene:clean.' } else { '' }
            if ($taskOutputOver) {
                $finding = Format-TaskOutputFinding -Largest $largestTaskOutputs `
                    -OverCount $taskOutputs.OverCount -Root $root.Path `
                    -MaxLength ($summaryCap - $summary.Length - $tail.Length - 1)
                $summary += " $finding"
            }
            $summary += $tail

            $result = New-HealthResult -Id $id -Category $category -Os 'windows' `
                -Severity $severity -Summary $summary -Commands $commands -Detail $detail `
                -NeedsAdmin $false -RanSuccessfully $true
        }
    }
}
. (Join-Path $PSScriptRoot '..\lib\Invoke-HealthCheckEnvelope.ps1')
