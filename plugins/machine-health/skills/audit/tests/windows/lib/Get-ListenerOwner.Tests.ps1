#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.DESCRIPTION
The netsh text below follows the shape of `netsh http show servicestate
view=requestq` captured on a Windows 11 host (build 26300): unindented
"Request queue name:" lines open each queue, "ID: <pid>, image: ..." lines
list its owners, and "Registered URLs:" lists URLs with their port. Ids,
service names and URL paths are made up.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ListenerOwner.ps1'

    $script:AppPath = Join-Path $TestDrive 'Tools\app.exe'
    $script:SvcPath = Join-Path $TestDrive 'Windows\svc host.exe'
    $script:QueuePath = Join-Path $TestDrive 'Windows\queue owner.exe'

    $script:RequestQueues = @'
Snapshot of HTTP service state (Request Queue View):
-----------------------------------------------------

Request queue name: Request queue is unnamed.
    Version: 2.0
    State: Active
    Number of active processes attached: 1
    Processes:
        ID: 500, image: <?>
        Services: ExampleSvc
    URL groups:
    URL group ID: FE00000620000001
        State: Active
        Request queue name: Request queue is unnamed.
        Properties:
            Number of registered URLs: 1
            Registered URLs:
                HTTP://*:5357/00000000-0000-0000-0000-000000000000/
        Server session ID: FF00000610000001
            Version: 2.0

Request queue name: Request queue is unnamed.
    Version: 2.0
    State: Active
    Number of active processes attached: 0
    Processes:
    URL groups:
    URL group ID: FE00000620000002
        State: Active
        Properties:
            Registered URLs:
                HTTPS://+:8443/orphan/
'@

    function Get-NotFoundError {
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('No matching objects found'), 'CmdletizationQuery_NotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
    }

    function Get-ByPort {
        param($Result)
        $byPort = @{}
        $Result.Listeners | ForEach-Object { $byPort["$($_.Protocol)/$($_.Port)"] = $_ }
        $byPort
    }
}

Describe 'ConvertTo-ExecutablePath' -Tag 'lib' {
    It 'reduces <Case>' -ForEach @(
        @{ Case = 'a quoted path with arguments'; In = '"X:\Program Files\Vendor\agent.exe" --service'; Out = 'X:\Program Files\Vendor\agent.exe' }
        @{ Case = 'an unquoted path with spaces and arguments'; In = 'X:\Program Files\Vendor\agent.exe -k netsvcs'; Out = 'X:\Program Files\Vendor\agent.exe' }
        @{ Case = 'a bare path'; In = 'X:\Tools\tool.exe'; Out = 'X:\Tools\tool.exe' }
        @{ Case = 'a native-namespace prefix'; In = '\??\X:\Drivers\kd.sys'; Out = 'X:\Drivers\kd.sys' }
    ) {
        ConvertTo-ExecutablePath -CommandLine $In | Should -Be $Out
    }

    It 'expands environment variables' {
        ConvertTo-ExecutablePath -CommandLine '%SystemRoot%\system32\svchost.exe -k x' |
            Should -Be (Join-Path $env:SystemRoot 'system32\svchost.exe')
    }
}

Describe 'ConvertFrom-HttpRequestQueue' -Tag 'lib' {
    It 'maps each registered port to its queue owner ids' {
        $map = ConvertFrom-HttpRequestQueue -Text $script:RequestQueues
        @($map[5357]) | Should -Be @(500)
    }

    It 'maps a port whose queue lists no owner to an empty list' {
        $map = ConvertFrom-HttpRequestQueue -Text $script:RequestQueues
        $map.ContainsKey(8443) | Should -BeTrue
        @($map[8443]).Count | Should -Be 0
    }

    It 'does not read a URL group or session id as an owner id' {
        $map = ConvertFrom-HttpRequestQueue -Text $script:RequestQueues
        @($map.Values | ForEach-Object { $_ }) | Should -Be @(500)
    }

    It 'returns an empty map for text with no queues' {
        (ConvertFrom-HttpRequestQueue -Text "Snapshot of HTTP service state:`n---").Count | Should -Be 0
    }
}

Describe 'Get-ListenerOwner' -Tag 'lib' {
    BeforeEach {
        Mock Get-NetTCPConnection {
            if ($State -eq 'Established') { return @([pscustomobject]@{ LocalAddress = '10.0.0.5'; LocalPort = 50000; OwningProcess = 100 }) }
            @(
                [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 8080; OwningProcess = 100 }
                [pscustomobject]@{ LocalAddress = '127.0.0.1'; LocalPort = 9000; OwningProcess = 200 }
                [pscustomobject]@{ LocalAddress = '::'; LocalPort = 445; OwningProcess = 4 }
                [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 5357; OwningProcess = 4 }
                [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 8443; OwningProcess = 4 }
                [pscustomobject]@{ LocalAddress = '192.168.1.20'; LocalPort = 7000; OwningProcess = 300 }
                [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 7100; OwningProcess = 400 }
            )
        }
        Mock Get-NetUDPEndpoint { @([pscustomobject]@{ LocalAddress = '::1'; LocalPort = 5353; OwningProcess = 200 }) }
        Mock Get-Process {
            @(
                [pscustomobject]@{ Id = 100; ProcessName = 'app'; Path = Join-Path $TestDrive 'reported\app.exe' }
                [pscustomobject]@{ Id = 200; ProcessName = 'svchost'; Path = $null }
                [pscustomobject]@{ Id = 300; ProcessName = 'mystery'; Path = $null }
                [pscustomobject]@{ Id = 400; ProcessName = 'tool'; Path = Join-Path $TestDrive 'Tools\tool.exe' }
                [pscustomobject]@{ Id = 500; ProcessName = 'svchost'; Path = $null }
            )
        }
        Mock Get-ProcessImagePath { if ($ProcessId -eq 100) { $script:AppPath } }
        Mock Get-CimInstance {
            @(
                [pscustomobject]@{ ProcessId = 200; Name = 'Svc'; PathName = "`"$($script:SvcPath)`" -k LocalService" }
                [pscustomobject]@{ ProcessId = 500; Name = 'ExampleSvc'; PathName = "`"$($script:QueuePath)`"" }
            )
        }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; IsOSBinary = $true } }
        Mock Invoke-NativeCommand { [pscustomobject]@{ status = 'Ok'; output = $script:RequestQueues } }
    }

    It 'resolves by kernel image, then process-reported path, then service, else unresolved' {
        $r = Get-ListenerOwner
        $r.ReadState | Should -Be 'ok'
        $r.EstablishedCount | Should -Be 1
        $byPort = Get-ByPort $r

        $byPort['tcp/8080'].PathSource | Should -Be 'process'
        $byPort['tcp/8080'].Path | Should -Be $script:AppPath -Because 'the kernel-reported image wins over the process-reported path'
        $byPort['tcp/8080'].BindScope | Should -Be 'any'

        $byPort['tcp/7100'].PathSource | Should -Be 'process-reported'
        $byPort['tcp/7100'].Path | Should -Be (Join-Path $TestDrive 'Tools\tool.exe')

        $byPort['tcp/9000'].PathSource | Should -Be 'service'
        $byPort['tcp/9000'].Path | Should -Be $script:SvcPath
        $byPort['tcp/9000'].BindScope | Should -Be 'loopback'

        $byPort['tcp/7000'].PathSource | Should -Be 'unresolved'
        $byPort['tcp/7000'].ProcessName | Should -Be 'mystery'
        $byPort['tcp/7000'].SignatureStatus | Should -BeNullOrEmpty
    }

    It 'traces an http.sys port to its request queue owner, and keeps a port with no queue as kernel' {
        $byPort = Get-ByPort (Get-ListenerOwner)
        $byPort['tcp/5357'].HttpSys | Should -BeTrue
        $byPort['tcp/5357'].Pid | Should -Be 500
        $byPort['tcp/5357'].PathSource | Should -Be 'service'
        $byPort['tcp/5357'].Path | Should -Be $script:QueuePath

        $byPort['tcp/445'].PathSource | Should -Be 'kernel'
        $byPort['tcp/445'].Path | Should -BeNullOrEmpty
        $byPort['tcp/445'].SignatureStatus | Should -BeNullOrEmpty
    }

    It 'leaves an http.sys port unresolved when its queue lists no owner' {
        $byPort = Get-ByPort (Get-ListenerOwner)
        $byPort['tcp/8443'].PathSource | Should -Be 'unresolved'
        $byPort['tcp/8443'].HttpSys | Should -BeTrue
    }

    It 'leaves every kernel TCP port unresolved when netsh output <Case>' -ForEach @(
        @{ Case = 'cannot be run'; Result = @{ status = 'Failed'; output = '' } }
        @{ Case = 'is empty'; Result = @{ status = 'Ok'; output = '' } }
    ) {
        $netshResult = [pscustomobject]$Result
        Mock Invoke-NativeCommand ({ $netshResult }.GetNewClosure())
        $byPort = Get-ByPort (Get-ListenerOwner)
        $byPort['tcp/445'].PathSource | Should -Be 'unresolved'
        $byPort['tcp/5357'].PathSource | Should -Be 'unresolved'
    }

    It 'runs netsh by its absolute path' {
        $null = Get-ListenerOwner
        Should -Invoke Invoke-NativeCommand -ParameterFilter { $Name -eq (Join-Path $env:SystemRoot 'System32\netsh.exe') }
    }

    It 'checks each unique binary signature once' {
        $null = Get-ListenerOwner
        Should -Invoke Get-AuthenticodeSignature -Times 4 -Exactly
    }

    It 'reports a signature read failure as UnknownError, not Valid' {
        Mock Get-AuthenticodeSignature { throw [System.IO.IOException]::new('locked') }
        ((Get-ListenerOwner).Listeners | Where-Object Port -eq 8080).SignatureStatus | Should -Be 'UnknownError'
    }

    It 'treats an empty socket table as absent, not a failure' {
        Mock Get-NetTCPConnection { Write-Error -ErrorRecord (Get-NotFoundError) }
        Mock Get-NetUDPEndpoint { Write-Error -ErrorRecord (Get-NotFoundError) }
        $r = Get-ListenerOwner
        $r.ReadState | Should -Be 'ok'
        @($r.Listeners).Count | Should -Be 0
    }

    It 'reports error when the socket table cannot be read' {
        Mock Get-NetTCPConnection { throw [System.InvalidOperationException]::new('provider failure') }
        (Get-ListenerOwner).ReadState | Should -Be 'error'
    }

    It 'leaves service-hosted listeners unresolved and records the failure when Win32_Service fails' {
        Mock Get-CimInstance { throw [System.UnauthorizedAccessException]::new('denied') }
        $r = Get-ListenerOwner
        $r.ServiceState | Should -Be 'denied'
        ($r.Listeners | Where-Object Port -eq 9000).PathSource | Should -Be 'unresolved'
    }
}
