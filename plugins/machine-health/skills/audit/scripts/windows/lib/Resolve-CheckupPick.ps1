#Requires -Version 7.4

<#
.SYNOPSIS
Resolve a payload copied from a checkup decision page against that run's id map.

.DESCRIPTION
The payload is untrusted text the owner pasted:

  checkup-picks
  picked: <row id> <row id> ... | none
  run: <lowercased run stamp>
  notes: <the owner's note, possibly several lines>

Its run: line names exactly one map, <ViewsDir>/checkup-<runStamp>.ids.json, and
only that file is opened. Everything from the first notes: line to the end is
the note, so a run: or picked: line typed inside the note is never read as one.

The whole payload is refused (a throw naming the run) when the first line is
not checkup-picks, picked: or run: is missing or repeated, another line comes
before notes:, the run stamp is malformed, or the map it names is gone (pruned
or never built) or is not a checkup-ids/1 map.

Otherwise one ResolvedPick is returned per distinct picked id: RowId, Action
(mute | approve), CheckId, FindingKey, Label, RemediationId, RunId, Notes, and
Refused, which is $null for a usable pick and the reason otherwise. An id that
does not match ^[a-z0-9-]{1,128}$ or is not in the map's rows is refused, and
so is a row whose check is not a shipped check, whose key is not a FindingKey,
or whose remediation is not shipped. A mute of an exclusion key under one of
$DefenderExclusionCheckIds (New-DefenderExclusionItem.ps1) resolves to one pick
per id in that list, each checked like any mute; under any other check it is
refused.

Reads files only; writes nothing. Setup writes each pick through
Set-ApprovalState after the owner's yes.
#>

. (Join-Path $PSScriptRoot 'Read-SharedText.ps1')
. (Join-Path $PSScriptRoot 'Resolve-SkillRoot.ps1')
. (Join-Path $PSScriptRoot 'ConvertFrom-Jsonc.ps1')
. (Join-Path $PSScriptRoot 'Get-RemediationId.ps1')
. (Join-Path $PSScriptRoot 'New-DefenderExclusionItem.ps1')

function Resolve-CheckupPick {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $ViewsDir,
        [Parameter(Mandatory = $true)] [AllowEmptyString()] [string] $Payload
    )

    $rowIdPattern = '^[a-z0-9-]{1,128}$'
    $keyPattern = '^[a-z-]{1,16}:[0-9a-f]{16}$'
    $stampPattern = '^[0-9]{4}-[0-9]{2}-[0-9]{2}t[0-9]{9}z$'
    $refuse = { param($Why) throw "Resolve-CheckupPick: payload refused: $Why" }

    if ($Payload.Length -gt 65536) { & $refuse 'it is longer than 64 KB.' }
    $lines = @(($Payload -replace "`r`n?", "`n").Trim() -split "`n")
    if ($lines[0].Trim() -cne 'checkup-picks') { & $refuse "the first line is not 'checkup-picks'." }

    $picked = @(); $run = @(); $notes = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        if ($line -cmatch '^notes:') {
            $notes = ((@($line.Substring(6)) + @($lines | Select-Object -Skip ($i + 1))) -join "`n").Trim()
            break
        }
        if ($line -cmatch '^picked:(.*)$') { $picked += , $Matches[1].Trim(); continue }
        if ($line -cmatch '^run:(.*)$') { $run += , $Matches[1].Trim(); continue }
        if ($line -ne '') { & $refuse "line $($i + 1) is not picked:, run: or notes:." }
    }
    if ($picked.Count -ne 1) { & $refuse 'it needs exactly one picked: line.' }
    if ($run.Count -ne 1) { & $refuse 'it needs exactly one run: line, naming the page it came from.' }
    $stamp = $run[0]
    if ($stamp -cnotmatch $stampPattern) { & $refuse "the run: value is not a run stamp." }
    if ([string]::IsNullOrEmpty($notes)) { $notes = $null }

    $fileStamp = $stamp.Substring(0, 10) + 'T' + $stamp.Substring(11, 9) + 'Z'
    $mapPath = Join-Path $ViewsDir "checkup-$fileStamp.ids.json"
    if (-not [System.IO.File]::Exists($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($mapPath))) {
        & $refuse "run $fileStamp has no id map in '$ViewsDir' (pruned or never built). Rerun the audit and pick from its page."
    }
    # JsonNode keeps every value as written; ConvertFrom-Json would turn a date-shaped string into a DateTime.
    $isObject = { param($Node) $Node -is [System.Text.Json.Nodes.JsonObject] }
    $str = {
        param($Node)
        if ($Node -is [System.Text.Json.Nodes.JsonValue] -and $Node.GetValueKind() -eq 'String') { $Node.GetValue[string]() } else { $null }
    }
    try {
        $map = [System.Text.Json.Nodes.JsonNode]::Parse((Read-SharedText -Path $mapPath))
    } catch {
        & $refuse "the id map of run $fileStamp is not JSON."
    }
    if (-not (& $isObject $map) -or (& $str $map['format']) -cne 'checkup-ids/1' -or -not (& $isObject $map['rows'])) {
        & $refuse "the id map of run $fileStamp is not a checkup-ids/1 map."
    }
    $runId = & $str $map['run_id']

    $catalog = Get-Content -LiteralPath (Join-Path (Resolve-SkillRoot) 'catalog\checks.jsonc') -Raw | ConvertFrom-Jsonc
    $shippedChecks = @($catalog.checks | ForEach-Object { [string]$_.id })
    $remediationIds = @(Get-RemediationId)

    $pick = {
        param($RowId, $Action, $CheckId, $FindingKey, $Label, $RemediationId, $Refused)
        [pscustomobject]@{
            RowId = $RowId; Action = $Action; CheckId = $CheckId; FindingKey = $FindingKey; Label = $Label
            RemediationId = $RemediationId; RunId = $runId; Notes = $notes; Refused = $Refused
        }
    }

    $ids = if ($picked[0] -ceq 'none' -or $picked[0] -eq '') { @() } else { @($picked[0] -split '\s+' | Select-Object -Unique) }
    foreach ($id in $ids) {
        if ($id -cnotmatch $rowIdPattern) {
            & $pick (Format-MachineText $id) $null $null $null $null $null 'not a row id'
            continue
        }
        $row = $map['rows'][$id]
        if (-not (& $isObject $row)) {
            & $pick $id $null $null $null $null $null "not a row of run $fileStamp"
            continue
        }
        $action = [string](& $str $row['action'])
        if ($action -ceq 'mute') {
            $checkId = [string](& $str $row['check_id']); $key = [string](& $str $row['finding_key'])
            $label = Format-MachineText (& $str $row['label'])
            $exclusion = $key.StartsWith('exclusion:')
            $checkIds = if ($exclusion -and $checkId -cin $script:DefenderExclusionCheckIds) { $script:DefenderExclusionCheckIds } else { @($checkId) }
            foreach ($c in $checkIds) {
                $why = if ($c -cnotin $shippedChecks) { "'$(Format-MachineText $c)' is not a shipped check" }
                elseif ($key -cnotmatch $keyPattern) { 'its key is not a FindingKey' }
                elseif ($exclusion -and $c -cnotin $script:DefenderExclusionCheckIds) { "an exclusion key belongs to $($script:DefenderExclusionCheckIds -join ' and ')" }
                & $pick $id 'mute' $c $key $label $null $why
            }
        } elseif ($action -ceq 'approve') {
            $remediation = [string](& $str $row['remediation_id'])
            $why = if ($remediation -cnotin $remediationIds) { "'$(Format-MachineText $remediation)' is not a shipped remediation" }
            & $pick $id 'approve' $null $null $null $remediation $why
        } else {
            & $pick $id $null $null $null $null $null 'its action is neither mute nor approve'
        }
    }
}
