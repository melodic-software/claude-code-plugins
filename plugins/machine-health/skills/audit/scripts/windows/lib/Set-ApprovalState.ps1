#Requires -Version 7.4

<#
.SYNOPSIS
Apply one owner decision to <StateBase>/state/approvals.json or mutes.json.

.DESCRIPTION
The sole writer of both files. Actions:

  mute     mutes.json: append { key, label, reason, added_at, run_id } to
           checks.<CheckId>.muted_findings; a key already there is skipped.
  unmute   mutes.json: remove the key under every check id.
  approve  approvals.json: remediations.<RemediationId> = { approved: true,
           approved_at, approved_by, notes }.
  revoke   approvals.json: remediations.<RemediationId>.approved = false and
           approved_at = now.

Arguments are validated first: CheckId must be a shipped check id, FindingKey
must match <kind>:<16 hex>, RemediationId must be a shipped remediation. Then
state/approvals.lock is held across one read, the change, the schema check and
one Write-StateFile replace, so a second writer waits and applies its change to
the file the first one wrote. A document that fails its schema is never
written. Writing under a cloud-synced StateBase is refused.

approved_by is "setup picks <RunId>" when a run id is given, else
"setup apply". Timestamps keep the local offset, as the other state files do.

Returns { Action, Path, Changed }; Changed is $false when nothing differed.
#>

. (Join-Path $PSScriptRoot 'Write-StateFile.ps1')
. (Join-Path $PSScriptRoot 'Enter-RunLock.ps1')
. (Join-Path $PSScriptRoot 'Assert-StateBaseLocation.ps1')
. (Join-Path $PSScriptRoot 'ConvertFrom-Jsonc.ps1')

function Set-ApprovalState {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)] [string] $StateBase,
        [Parameter(Mandatory = $true)] [ValidateSet('mute', 'unmute', 'approve', 'revoke')] [string] $Action,
        [string] $CheckId,
        [string] $FindingKey,
        [string] $RemediationId,
        [string] $Label,
        [string] $Notes,
        [string] $RunId,
        [ValidateRange(0, 600)] [int] $LockTimeoutSeconds = 30
    )

    $request = @{
        CheckId = $CheckId; FindingKey = $FindingKey; RemediationId = $RemediationId
        Label = $Label; Notes = $Notes; RunId = $RunId
    }
    $catalogRoot = Join-Path $PSScriptRoot '..\..\..\catalog'
    $remediationIds = @('restart-stopped-service', 'clear-temp-files')
    $keyPattern = '^[a-z-]{1,16}:[0-9a-f]{16}$'
    $now = (Get-Date).ToString('o')
    $orNull = { param($Value) if ([string]::IsNullOrEmpty($Value)) { $null } else { [System.Text.Json.Nodes.JsonValue]::Create([string]$Value) } }

    $assertKey = {
        if ($request.FindingKey -cnotmatch $keyPattern) {
            throw "Set-ApprovalState: finding key '$($request.FindingKey)' does not match <kind>:<16 hex>."
        }
    }
    $assertRemediation = {
        if ($request.RemediationId -notin $remediationIds) {
            throw "Set-ApprovalState: '$($request.RemediationId)' is not a shipped remediation ($($remediationIds -join ', '))."
        }
    }
    $remediationsOf = {
        param($Doc)
        if ($null -eq $Doc['remediations']) { $Doc['remediations'] = [System.Text.Json.Nodes.JsonObject]::new() }
        return , $Doc['remediations']
    }

    $mutesFile = @{ Name = 'mutes.json'; Schema = 'mutes.schema.json'; Root = 'checks' }
    $approvalsFile = @{ Name = 'approvals.json'; Schema = 'approvals.schema.json'; Root = 'remediations' }
    $actions = @{
        mute    = @{
            File     = $mutesFile
            Validate = {
                $shipped = @((Get-Content -LiteralPath (Join-Path $catalogRoot 'checks.jsonc') -Raw |
                            ConvertFrom-Jsonc).checks | ForEach-Object { [string]$_.id })
                if ($request.CheckId -notin $shipped) { throw "Set-ApprovalState: '$($request.CheckId)' is not a shipped check id." }
                & $assertKey
            }
            Apply    = {
                param($Doc)
                $checks = $Doc['checks']
                if ($null -eq $checks[$request.CheckId]) {
                    $checks[$request.CheckId] = [System.Text.Json.Nodes.JsonObject]::new()
                    $checks[$request.CheckId]['muted_findings'] = [System.Text.Json.Nodes.JsonArray]::new()
                }
                $list = $checks[$request.CheckId]['muted_findings']
                foreach ($item in $list) {
                    if ($item['key'].GetValue[string]() -ceq $request.FindingKey) { return $false }
                }
                $entry = [System.Text.Json.Nodes.JsonObject]::new()
                $entry['key'] = $request.FindingKey
                $entry['label'] = & $orNull $request.Label
                $entry['reason'] = & $orNull $request.Notes
                $entry['added_at'] = $now
                $entry['run_id'] = & $orNull $request.RunId
                $list.Add($entry)
                return $true
            }
        }
        unmute  = @{
            File     = $mutesFile
            Validate = $assertKey
            Apply    = {
                param($Doc)
                $removed = 0
                foreach ($pair in $Doc['checks']) {
                    $list = $pair.Value['muted_findings']
                    for ($i = $list.Count - 1; $i -ge 0; $i--) {
                        if ($list[$i]['key'].GetValue[string]() -ceq $request.FindingKey) { $list.RemoveAt($i); $removed++ }
                    }
                }
                if ($removed -eq 0) { throw "Set-ApprovalState: '$($request.FindingKey)' is not muted under any check." }
                return $true
            }
        }
        approve = @{
            File     = $approvalsFile
            Validate = $assertRemediation
            Apply    = {
                param($Doc)
                $entry = [System.Text.Json.Nodes.JsonObject]::new()
                $entry['approved'] = $true
                $entry['approved_at'] = $now
                $entry['approved_by'] = if ($request.RunId) { "setup picks $($request.RunId)" } else { 'setup apply' }
                $entry['notes'] = & $orNull $request.Notes
                (& $remediationsOf $Doc)[$request.RemediationId] = $entry
                return $true
            }
        }
        revoke  = @{
            File     = $approvalsFile
            Validate = $assertRemediation
            Apply    = {
                param($Doc)
                $remediations = & $remediationsOf $Doc
                $id = $request.RemediationId
                if ($null -eq $remediations[$id]) { $remediations[$id] = [System.Text.Json.Nodes.JsonObject]::new() }
                $remediations[$id]['approved'] = $false
                $remediations[$id]['approved_at'] = $now
                return $true
            }
        }
    }

    $spec = $actions[$Action]
    & $spec.Validate

    $location = Assert-StateBaseLocation -Path $StateBase
    if ($location.Synced) {
        throw ("Set-ApprovalState: refusing to write: '$StateBase' is under a cloud sync root " +
            "($($location.Rule): '$($location.Folder)'). Move the plugin state folder out of it.")
    }

    $stateDir = Join-Path $StateBase 'state'
    $target = Join-Path $stateDir $spec.File.Name
    if (-not $PSCmdlet.ShouldProcess($target, $Action)) { return }
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force -ErrorAction Stop | Out-Null
    }

    $lock = Enter-RunLock -StateDir $stateDir -Name 'approvals' -TimeoutSeconds $LockTimeoutSeconds
    if ($null -eq $lock) {
        throw "Set-ApprovalState: '$(Join-Path $stateDir 'approvals.lock')' is held by another writer; gave up after $LockTimeoutSeconds s."
    }
    try {
        $schemaPath = Join-Path $catalogRoot "schemas\$($spec.File.Schema)"
        $jsonOptions = [System.Text.Json.JsonSerializerOptions]@{
            WriteIndented = $true
            Encoder       = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
        }
        $written = Write-StateFile -Path $target -Update {
            param($Current)
            if ([string]::IsNullOrWhiteSpace($Current)) {
                $doc = [System.Text.Json.Nodes.JsonObject]::new()
                $doc['schema_version'] = '1.0'
                $doc[$spec.File.Root] = [System.Text.Json.Nodes.JsonObject]::new()
            } else {
                $doc = [System.Text.Json.Nodes.JsonNode]::Parse($Current)
            }
            if (-not (& $spec.Apply $doc)) { return $null }
            $text = $doc.ToJsonString($jsonOptions)
            $schemaErrors = $null
            if (-not (Test-Json -Json $text -SchemaFile $schemaPath -ErrorAction SilentlyContinue -ErrorVariable schemaErrors)) {
                throw "Set-ApprovalState: the result does not match $($spec.File.Schema); '$target' left as it is. $($schemaErrors -join ' ')"
            }
            return $text
        }
    } finally {
        $lock.Dispose()
    }

    return [pscustomobject]@{ Action = $Action; Path = $target; Changed = [bool]$written }
}
