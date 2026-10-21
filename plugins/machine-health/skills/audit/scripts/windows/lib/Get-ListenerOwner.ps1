#Requires -Version 7.4

<#
.SYNOPSIS
Lists the listening TCP and UDP endpoints with the program that owns each, and
returns plain listener records plus a ReadState.

.DESCRIPTION
Every endpoint carries its owning process id unelevated. The id resolves to a
binary in this order: the process's own path (Get-Process, one bulk call),
then Win32_Service.PathName for a service host the caller cannot open, else
unresolved. Process ids 0 and 4 are the kernel (http.sys and friends): they
have no file and are never called unsigned.

A service PathName is normalized to the same form as a process path (quotes
and arguments removed, environment variables expanded), so a listener keeps
one identity whether it was resolved elevated or not. Each unique path gets
one Get-AuthenticodeSignature call.

Read-only, unelevated.
#>

$script:KernelPids = @(0, 4)

function ConvertTo-ExecutablePath {
    <#
    .SYNOPSIS
    Reduces a command line (a service PathName) to the executable path alone.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string] $CommandLine)

    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }
    $text = [System.Environment]::ExpandEnvironmentVariables($CommandLine.Trim())
    if ($text.StartsWith('\??\')) { $text = $text.Substring(4) }
    if ($text.StartsWith('"')) {
        $end = $text.IndexOf('"', 1)
        return $end -gt 1 ? $text.Substring(1, $end - 1) : $text.Trim('"')
    }
    if ($text -match '^(?<exe>.+?\.exe)(\s|$)') { return $Matches['exe'] }
    return ($text -split '\s+', 2)[0]
}

function Get-BindScope {
    [CmdletBinding()]
    [OutputType([string])]
    param([AllowNull()] [AllowEmptyString()] [string] $Address)

    if ($Address -in @('0.0.0.0', '::')) { return 'any' }
    $ip = $null
    if ([System.Net.IPAddress]::TryParse([string]$Address, [ref]$ip) -and [System.Net.IPAddress]::IsLoopback($ip)) {
        return 'loopback'
    }
    return 'specific'
}

function Get-ListenerReadState {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [System.Management.Automation.ErrorRecord] $ErrorRecord)

    if ($ErrorRecord.CategoryInfo.Category -eq 'ObjectNotFound') { return 'absent' }
    if ($ErrorRecord.CategoryInfo.Category -eq 'PermissionDenied' -or
        $ErrorRecord.Exception -is [System.UnauthorizedAccessException]) { return 'denied' }
    return 'error'
}

function Get-ListenerOwner {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $result = [pscustomobject]@{
        ReadState        = 'ok'
        ServiceState     = 'ok'
        EstablishedCount = 0
        Listeners        = @()
    }

    $endpoints = [System.Collections.Generic.List[pscustomobject]]::new()
    try {
        foreach ($c in @(Get-NetTCPConnection -State Listen -ErrorAction Stop)) {
            $endpoints.Add([pscustomobject]@{ Protocol = 'tcp'; Address = [string]$c.LocalAddress; Port = [int]$c.LocalPort; Pid = [int]$c.OwningProcess })
        }
    } catch {
        # No listening socket at all comes back as "not found", which is an empty table, not a failure.
        $state = Get-ListenerReadState -ErrorRecord $_
        if ($state -ne 'absent') { $result.ReadState = $state }
    }
    try {
        foreach ($u in @(Get-NetUDPEndpoint -ErrorAction Stop)) {
            $endpoints.Add([pscustomobject]@{ Protocol = 'udp'; Address = [string]$u.LocalAddress; Port = [int]$u.LocalPort; Pid = [int]$u.OwningProcess })
        }
    } catch {
        $state = Get-ListenerReadState -ErrorRecord $_
        if ($state -ne 'absent' -and $result.ReadState -eq 'ok') { $result.ReadState = $state }
    }
    try {
        $result.EstablishedCount = @(Get-NetTCPConnection -State Established -ErrorAction Stop).Count
    } catch {
        $state = Get-ListenerReadState -ErrorRecord $_
        if ($state -ne 'absent' -and $result.ReadState -eq 'ok') { $result.ReadState = $state }
    }

    $processes = @{}
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $processes[[int]$p.Id] = [pscustomobject]@{ Name = [string]$p.ProcessName; Path = [string]$p.Path }
    }

    $services = @{}
    try {
        foreach ($s in @(Get-CimInstance -ClassName Win32_Service -Property ProcessId, PathName, Name -ErrorAction Stop)) {
            $servicePid = [int]$s.ProcessId
            if ($servicePid -gt 0 -and -not $services.ContainsKey($servicePid)) {
                $services[$servicePid] = ConvertTo-ExecutablePath -CommandLine ([string]$s.PathName)
            }
        }
    } catch {
        $result.ServiceState = Get-ListenerReadState -ErrorRecord $_
        if ($result.ServiceState -eq 'absent') { $result.ServiceState = 'error' }
    }

    $signatures = @{}
    $listeners = foreach ($e in $endpoints) {
        $proc = $processes[$e.Pid]
        $name = if ($proc) { $proc.Name } else { $null }
        $path = $null
        $source = 'unresolved'
        if ($e.Pid -in $script:KernelPids) {
            $source = 'kernel'
            $name = 'System'
        } elseif ($proc -and $proc.Path) {
            $path = $proc.Path
            $source = 'process'
        } elseif ($services[$e.Pid]) {
            $path = $services[$e.Pid]
            $source = 'service'
        }

        $status = $null
        $isOs = $null
        if ($path) {
            $sigKey = $path.ToLowerInvariant()
            if (-not $signatures.ContainsKey($sigKey)) {
                $signatures[$sigKey] = try {
                    $sig = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
                    [pscustomobject]@{ Status = [string]$sig.Status; IsOsBinary = [bool]$sig.IsOSBinary }
                } catch {
                    [pscustomobject]@{ Status = 'UnknownError'; IsOsBinary = $false }
                }
            }
            $status = $signatures[$sigKey].Status
            $isOs = $signatures[$sigKey].IsOsBinary
        }

        [pscustomobject]@{
            Protocol        = $e.Protocol
            LocalAddress    = $e.Address
            Port            = $e.Port
            BindScope       = Get-BindScope -Address $e.Address
            Pid             = $e.Pid
            ProcessName     = $name
            Path            = $path
            PathSource      = $source
            SignatureStatus = $status
            IsOsBinary      = $isOs
        }
    }

    $result.Listeners = @($listeners)
    return $result
}
