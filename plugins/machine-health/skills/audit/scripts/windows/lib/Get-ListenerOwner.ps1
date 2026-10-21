#Requires -Version 7.4

<#
.SYNOPSIS
Lists the listening TCP and UDP endpoints with the program that owns each, and
returns plain listener records plus a ReadState.

.DESCRIPTION
Every endpoint carries its owning process id unelevated. The id resolves to a
binary in this order, and PathSource names the step that answered:
  1. process: the image path the kernel reports for the process
     (QueryFullProcessImageNameW with PROCESS_QUERY_LIMITED_INFORMATION);
  2. process-reported: Get-Process's Path, which the process itself can
     influence, used only when step 1 fails;
  3. service: the PathName of the Win32_Service hosted in that process;
  4. unresolved.

Process ids 0 and 4 are the kernel. A kernel TCP port served by http.sys is
traced to the process that owns its request queue, read from
`netsh http show servicestate view=requestq` (absolute path; its output is
untrusted text, parsed for queue owner ids and registered URL ports only);
that process then resolves as above and the record says HttpSys. A kernel
port with no request queue (SMB, NetBIOS) stays 'kernel'. A port whose queue
owner cannot be resolved, or any kernel TCP port when that output cannot be
read, is unresolved.

A service PathName is reduced to the executable path (quotes and arguments
removed, environment variables expanded), so a listener keeps one identity
whether it was resolved elevated or not. Each unique path gets one
Get-AuthenticodeSignature call. Read-only, unelevated.
#>

. (Join-Path $PSScriptRoot 'Invoke-NativeCommand.ps1')

$script:KernelPids = @(0, 4)
$script:ProcessQueryLimitedInformation = 0x1000

function Get-ProcessImagePath {
    <#
    .SYNOPSIS
    The kernel-reported image path of one process, or $null when it cannot be opened.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter(Mandatory = $true)] [int] $ProcessId)

    if (-not ('MachineHealth.ProcessImage' -as [type])) {
        Add-Type -Namespace MachineHealth -Name ProcessImage -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)]
public static extern IntPtr OpenProcess(uint access, bool inherit, int processId);
[DllImport("kernel32.dll", SetLastError = true)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool CloseHandle(IntPtr handle);
[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
[return: MarshalAs(UnmanagedType.Bool)]
public static extern bool QueryFullProcessImageNameW(IntPtr process, uint flags, System.Text.StringBuilder name, ref uint size);
public static string GetImagePath(int processId, uint access) {
    IntPtr handle = OpenProcess(access, false, processId);
    if (handle == IntPtr.Zero) { return null; }
    try {
        var name = new System.Text.StringBuilder(32768);
        uint size = (uint)name.Capacity;
        return QueryFullProcessImageNameW(handle, 0, name, ref size) ? name.ToString(0, (int)size) : null;
    } finally {
        CloseHandle(handle);
    }
}
'@
    }
    return [MachineHealth.ProcessImage]::GetImagePath($ProcessId, $script:ProcessQueryLimitedInformation)
}

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

function ConvertFrom-HttpRequestQueue {
    <#
    .SYNOPSIS
    Maps each registered URL port to the owner process ids of its request
    queue, from netsh's request-queue view. A port whose queue lists no owner
    maps to an empty list.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([AllowEmptyString()] [string] $Text = '')

    $map = @{}
    $pids = [System.Collections.Generic.List[int]]::new()
    $ports = [System.Collections.Generic.List[int]]::new()
    $flush = {
        foreach ($port in $ports) {
            if (-not $map.ContainsKey($port)) { $map[$port] = [System.Collections.Generic.List[int]]::new() }
            foreach ($owner in $pids) { if (-not $map[$port].Contains($owner)) { $map[$port].Add($owner) } }
        }
        $pids.Clear()
        $ports.Clear()
    }
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^\S') {
            . $flush
        } elseif ($line -match '^\s+ID:\s*(?<id>\d+)\b') {
            $pids.Add([int]$Matches['id'])
        } elseif ($line -match '(?i)^\s*https?://[^/\s]*:(?<port>\d+)(/|\s|$)') {
            $ports.Add([int]$Matches['port'])
        }
    }
    . $flush
    return $map
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

    $queues = $null
    if (@($endpoints | Where-Object { $_.Protocol -eq 'tcp' -and $_.Pid -in $script:KernelPids }).Count -gt 0) {
        $netsh = Invoke-NativeCommand -Name (Join-Path $env:SystemRoot 'System32\netsh.exe') `
            -ArgumentList @('http', 'show', 'servicestate', 'view=requestq') -DiscardStdErr
        if ($netsh.status -eq 'Ok' -and $netsh.output) { $queues = ConvertFrom-HttpRequestQueue -Text $netsh.output }
    }

    $images = @{}
    $resolve = {
        param([int] $ProcessId)
        $proc = $processes[$ProcessId]
        if (-not $images.ContainsKey($ProcessId)) {
            $images[$ProcessId] = try { Get-ProcessImagePath -ProcessId $ProcessId } catch { $null }
        }
        $name = if ($proc) { $proc.Name } else { $null }
        if ($images[$ProcessId]) { return [pscustomobject]@{ Name = $name; Path = $images[$ProcessId]; Source = 'process' } }
        if ($proc -and $proc.Path) { return [pscustomobject]@{ Name = $name; Path = $proc.Path; Source = 'process-reported' } }
        if ($services[$ProcessId]) { return [pscustomobject]@{ Name = $name; Path = $services[$ProcessId]; Source = 'service' } }
        return [pscustomobject]@{ Name = $name; Path = $null; Source = 'unresolved' }
    }

    $signatures = @{}
    $listeners = foreach ($e in $endpoints) {
        $owners = @($e.Pid)
        $httpSys = $false
        $kernel = $e.Pid -in $script:KernelPids
        if ($kernel -and $e.Protocol -eq 'tcp') {
            if ($null -eq $queues) {
                $owners = @($null)
            } elseif ($queues.ContainsKey($e.Port)) {
                $httpSys = $true
                $owners = @($queues[$e.Port])
                if ($owners.Count -eq 0) { $owners = @($null) }
            }
        }

        foreach ($owner in $owners) {
            $found = if ($kernel -and -not $httpSys -and $null -ne $owner) {
                [pscustomobject]@{ Name = 'System'; Path = $null; Source = 'kernel' }
            } elseif ($null -eq $owner) {
                [pscustomobject]@{ Name = 'System'; Path = $null; Source = 'unresolved' }
            } else {
                & $resolve $owner
            }

            $status = $null
            $isOs = $null
            if ($found.Path) {
                $sigKey = $found.Path.ToLowerInvariant()
                if (-not $signatures.ContainsKey($sigKey)) {
                    $signatures[$sigKey] = try {
                        $sig = Get-AuthenticodeSignature -LiteralPath $found.Path -ErrorAction Stop
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
                Pid             = if ($null -ne $owner) { $owner } else { $e.Pid }
                ProcessName     = $found.Name
                Path            = $found.Path
                PathSource      = $found.Source
                HttpSys         = $httpSys
                SignatureStatus = $status
                IsOsBinary      = $isOs
            }
        }
    }

    $result.Listeners = @($listeners)
    return $result
}
