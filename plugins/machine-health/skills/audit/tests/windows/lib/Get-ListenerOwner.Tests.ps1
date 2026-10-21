#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-ListenerOwner.ps1'

    $script:AppPath = Join-Path $TestDrive 'Tools\app.exe'
    $script:SvcPath = Join-Path $TestDrive 'Windows\svc host.exe'

    function Get-NotFoundError {
        [System.Management.Automation.ErrorRecord]::new(
            [System.Exception]::new('No matching objects found'), 'CmdletizationQuery_NotFound',
            [System.Management.Automation.ErrorCategory]::ObjectNotFound, $null)
    }
}

Describe 'ConvertTo-ExecutablePath' -Tag 'lib' {
    It 'reduces <Case>' -TestCases @(
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

Describe 'Get-ListenerOwner' -Tag 'lib' {
    BeforeEach {
        Mock Get-NetTCPConnection {
            if ($State -eq 'Established') { return @([pscustomobject]@{ LocalAddress = '10.0.0.5'; LocalPort = 50000; OwningProcess = 100 }) }
            @(
                [pscustomobject]@{ LocalAddress = '0.0.0.0'; LocalPort = 8080; OwningProcess = 100 }
                [pscustomobject]@{ LocalAddress = '127.0.0.1'; LocalPort = 9000; OwningProcess = 200 }
                [pscustomobject]@{ LocalAddress = '::'; LocalPort = 445; OwningProcess = 4 }
                [pscustomobject]@{ LocalAddress = '192.168.1.20'; LocalPort = 7000; OwningProcess = 300 }
            )
        }
        Mock Get-NetUDPEndpoint { @([pscustomobject]@{ LocalAddress = '::1'; LocalPort = 5353; OwningProcess = 200 }) }
        Mock Get-Process {
            @(
                [pscustomobject]@{ Id = 100; ProcessName = 'app'; Path = $script:AppPath }
                [pscustomobject]@{ Id = 200; ProcessName = 'svchost'; Path = $null }
                [pscustomobject]@{ Id = 300; ProcessName = 'mystery'; Path = $null }
                [pscustomobject]@{ Id = 4; ProcessName = 'System'; Path = $null }
            )
        }
        Mock Get-CimInstance { @([pscustomobject]@{ ProcessId = 200; Name = 'Svc'; PathName = "`"$($script:SvcPath)`" -k LocalService" }) }
        Mock Get-AuthenticodeSignature { [pscustomobject]@{ Status = 'Valid'; IsOSBinary = $true } }
    }

    It 'resolves by process path, then service path, then kernel, else unresolved' {
        $r = Get-ListenerOwner
        $r.ReadState | Should -Be 'ok'
        $r.EstablishedCount | Should -Be 1
        $byPort = @{}
        $r.Listeners | ForEach-Object { $byPort["$($_.Protocol)/$($_.Port)"] = $_ }

        $byPort['tcp/8080'].PathSource | Should -Be 'process'
        $byPort['tcp/8080'].Path | Should -Be $script:AppPath
        $byPort['tcp/8080'].BindScope | Should -Be 'any'

        $byPort['tcp/9000'].PathSource | Should -Be 'service'
        $byPort['tcp/9000'].Path | Should -Be $script:SvcPath
        $byPort['tcp/9000'].BindScope | Should -Be 'loopback'
        $byPort['udp/5353'].BindScope | Should -Be 'loopback'

        $byPort['tcp/445'].PathSource | Should -Be 'kernel'
        $byPort['tcp/445'].Path | Should -BeNullOrEmpty
        $byPort['tcp/445'].SignatureStatus | Should -BeNullOrEmpty

        $byPort['tcp/7000'].PathSource | Should -Be 'unresolved'
        $byPort['tcp/7000'].ProcessName | Should -Be 'mystery'
        $byPort['tcp/7000'].BindScope | Should -Be 'specific'
        $byPort['tcp/7000'].SignatureStatus | Should -BeNullOrEmpty
    }

    It 'checks each unique binary signature once' {
        $null = Get-ListenerOwner
        Should -Invoke Get-AuthenticodeSignature -Times 2 -Exactly
    }

    It 'reports a signature read failure as UnknownError, not Valid' {
        Mock Get-AuthenticodeSignature { throw [System.IO.IOException]::new('locked') }
        $l = (Get-ListenerOwner).Listeners | Where-Object Port -eq 8080
        $l.SignatureStatus | Should -Be 'UnknownError'
    }

    It 'treats an empty socket table as absent, not a failure' {
        Mock Get-NetTCPConnection { Write-Error -ErrorRecord (Get-NotFoundError) }
        Mock Get-NetUDPEndpoint { Write-Error -ErrorRecord (Get-NotFoundError) }
        $r = Get-ListenerOwner
        $r.ReadState | Should -Be 'ok'
        @($r.Listeners).Count | Should -Be 0
        $r.EstablishedCount | Should -Be 0
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
