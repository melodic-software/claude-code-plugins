#Requires -Version 7.4

<#
.SYNOPSIS
Wrapper around Invoke-WebRequest that enforces a host allowlist and logs every
call to the run log. Used by any check/lib that needs outbound HTTP.

.DESCRIPTION
SKILL.md mandates an egress allowlist: every outbound URL must be logged and
must match one of a small set of authoritative hosts. This wrapper centralizes
both concerns so individual check authors don't have to reimplement the
policy. Callers that ship egress but don't route through this wrapper are a
review red flag.

Allowlist is host-pattern based. Exact host match wins; leading-wildcard
patterns (e.g. '*.update.microsoft.com') match any subdomain.

Return: the Invoke-WebRequest response object. On failure the wrapper logs a
FAIL line and re-throws so callers can decide whether to fall back.

Neutrally named for future port to scripts/macos/lib/ (the Invoke-WebRequest
cmdlet is cross-platform in PowerShell 7).
#>

$script:EgressAllowlist = @(
    'cisa.gov'
    'www.cisa.gov'
    'update.microsoft.com'
    '*.update.microsoft.com'
    'windowsupdate.com'
    '*.windowsupdate.com'
    'catalog.update.microsoft.com'
    '*.winget.microsoft.com'
    'cdn.winget.microsoft.com'
    'pkgmgr.blob.core.windows.net'
)

function Test-EgressHostAllowed {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)] [string] $HostName
    )

    $h = $HostName.ToLowerInvariant()
    foreach ($pattern in $script:EgressAllowlist) {
        $p = $pattern.ToLowerInvariant()
        if ($p -eq $h) { return $true }
        if ($p.StartsWith('*.') -and $h.EndsWith($p.Substring(1))) {
            return $true
        }
    }
    return $false
}

function Get-EgressAllowlist {
    [CmdletBinding()]
    [OutputType([object[]])]
    param()
    return , ([string[]]@($script:EgressAllowlist))
}

function Invoke-AllowlistedWeb {
    [CmdletBinding()]
    [OutputType([Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject])]
    param(
        [Parameter(Mandatory = $true)] [string] $Uri,
        [string] $LogPath,
        [int] $TimeoutSec = 30,
        [string] $OutFile,
        [hashtable] $Headers
    )

    $parsed = $null
    try {
        $parsed = [System.Uri]$Uri
    } catch {
        $msg = "Invoke-AllowlistedWeb: malformed URI '$Uri': $($_.Exception.Message)"
        Write-EgressLogLine -LogPath $LogPath -Kind 'FAIL' -Uri $Uri -Message $msg
        throw $msg
    }

    if (-not (Test-EgressHostAllowed -HostName $parsed.Host)) {
        $msg = "Invoke-AllowlistedWeb: host '$($parsed.Host)' not on egress allowlist."
        Write-EgressLogLine -LogPath $LogPath -Kind 'DENY' -Uri $Uri -Message $msg
        throw $msg
    }

    Write-EgressLogLine -LogPath $LogPath -Kind 'GET' -Uri $Uri

    $webParams = @{
        Uri             = $Uri
        UseBasicParsing = $true
        TimeoutSec      = $TimeoutSec
        ErrorAction     = 'Stop'
    }
    if ($OutFile) { $webParams['OutFile'] = $OutFile }
    if ($Headers) { $webParams['Headers'] = $Headers }

    try {
        return Invoke-WebRequest @webParams
    } catch {
        $msg = $_.Exception.Message
        Write-EgressLogLine -LogPath $LogPath -Kind 'FAIL' -Uri $Uri -Message $msg
        throw
    }
}

function Write-EgressLogLine {
    [CmdletBinding()]
    param(
        [string] $LogPath,
        [Parameter(Mandatory = $true)] [ValidateSet('GET', 'FAIL', 'DENY')] [string] $Kind,
        [Parameter(Mandatory = $true)] [string] $Uri,
        [string] $Message
    )
    if (-not $LogPath) { return }
    $line = "$((Get-Date).ToString('o')) egress $Kind $Uri"
    if ($Message) { $line = "$line - $Message" }
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding utf8
    } catch {
        # Egress log writes back the audit trail the orchestrator reads into
        # `urls_called`. Swallowing failures would corrupt that snapshot with
        # no signal. Surface via stderr so the run log and any terminal
        # observer both capture the dropped entry.
        $err = "egress log write failed ($($_.Exception.Message)). Dropped: $line"
        [Console]::Error.WriteLine("[machine-health] $err")
    }
}

function Read-EgressLog {
    <#
    .SYNOPSIS
    Parse the run log for egress GET/FAIL/DENY lines emitted by the wrapper
    OR by legacy callers (Get-CisaKevCache writes matching "egress GET/FAIL"
    lines directly). Returns an array of {timestamp, kind, uri, message} for
    the orchestrator to populate `urls_called` in the run snapshot.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)] [string] $LogPath
    )

    if (-not (Test-Path -LiteralPath $LogPath)) { return @() }

    $entries = [System.Collections.Generic.List[pscustomobject]]::new()
    try {
        $lines = Get-Content -LiteralPath $LogPath -ErrorAction Stop
    } catch {
        Write-Verbose "Read-EgressLog: read failed ($($_.Exception.Message))."
        return @()
    }

    foreach ($line in $lines) {
        if ($line -match '^(?<ts>\S+)\s+egress\s+(?<kind>GET|FAIL|DENY)\s+(?<uri>\S+)(\s+-\s+(?<msg>.*))?$') {
            $entries.Add([pscustomobject]@{
                    timestamp = $Matches['ts']
                    kind      = $Matches['kind']
                    uri       = $Matches['uri']
                    message   = $Matches['msg']
                })
        }
    }
    return $entries.ToArray()
}
