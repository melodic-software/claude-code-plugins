#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Get-MutedFindingKey.ps1 -- the read-only
mutes.json reader and the per-check muted key lookup -- and for
catalog/schemas/mutes.schema.json.

.DESCRIPTION
Get-MuteState runs in modes that must leave the state folder alone, so these
tests pin that it creates nothing, migrates nothing, and falls back to no
mutes on a missing or broken file.
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'Get-MutedFindingKey.ps1'
    $script:SchemaPath = Join-Path $script:SkillRoot 'catalog\schemas\mutes.schema.json'

    $script:ExampleJson = @'
{
  "schema_version": "1.0",
  "checks": {
    "startup-items": {
      "muted_findings": [
        { "key": "startup:7eef5f7d094fe8c0", "label": "Updater", "reason": null,
          "added_at": "2026-10-21T12:00:00Z", "run_id": "2026-10-21T08:00:00.0000000-04:00" }
      ]
    },
    "browser-extensions": {
      "muted_findings": [
        { "key": "ext:dfe36cc7950bcbf3", "added_at": "2026-10-21T12:00:00Z" },
        { "key": "ext:3f9a0c1d2e4b5a67", "label": null, "reason": "work profile",
          "added_at": "2026-10-21T12:00:00Z", "run_id": null }
      ]
    }
  }
}
'@
}

Describe 'mutes.schema.json' -Tag 'lib' {
    It 'accepts the documented example' {
        Test-Json -Json $script:ExampleJson -SchemaFile $script:SchemaPath | Should -BeTrue
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an entry without added_at'; Entry = '{ "key": "ext:dfe36cc7950bcbf3" }' }
        @{ Case = 'an entry with an extra property'; Entry = '{ "key": "ext:dfe36cc7950bcbf3", "added_at": "2026-10-21T12:00:00Z", "approved": true }' }
        @{ Case = 'a key without 16 hex characters'; Entry = '{ "key": "ext:dfe36cc7", "added_at": "2026-10-21T12:00:00Z" }' }
        @{ Case = 'a key with an uppercase kind'; Entry = '{ "key": "EXT:dfe36cc7950bcbf3", "added_at": "2026-10-21T12:00:00Z" }' }
    ) {
        $json = '{ "schema_version": "1.0", "checks": { "browser-extensions": { "muted_findings": [ ' + $Entry + ' ] } } }'
        Test-Json -Json $json -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'rejects a schema_version other than 1.0' {
        $json = '{ "schema_version": "2.0", "checks": {} }'
        Test-Json -Json $json -SchemaFile $script:SchemaPath -ErrorAction SilentlyContinue | Should -BeFalse
    }
}

Describe 'Get-MuteState and Get-MutedFindingKey' -Tag 'lib' {
    BeforeEach {
        $script:base = Join-Path $TestDrive ([guid]::NewGuid().ToString('n'))
        New-Item -ItemType Directory -Path $script:base | Out-Null
        $script:stateDir = Join-Path $script:base 'state'
        $script:mutesPath = Join-Path $script:stateDir 'mutes.json'
    }

    Context 'a valid mutes.json' {
        BeforeEach {
            New-Item -ItemType Directory -Path $script:stateDir | Out-Null
            Set-Content -LiteralPath $script:mutesPath -Value $script:ExampleJson -Encoding utf8
        }

        It 'returns the keys muted under the given check id only' {
            $state = Get-MuteState -StateDir $script:stateDir
            $keys = Get-MutedFindingKey -State $state -CheckId 'browser-extensions'
            $keys | Should -Be @('ext:dfe36cc7950bcbf3', 'ext:3f9a0c1d2e4b5a67')
            $keys = Get-MutedFindingKey -State $state -CheckId 'startup-items'
            $keys | Should -Be @('startup:7eef5f7d094fe8c0')
        }

        It 'returns a string[] even for a single key' {
            $state = Get-MuteState -StateDir $script:stateDir
            $keys = Get-MutedFindingKey -State $state -CheckId 'startup-items'
            , $keys | Should -BeOfType [string[]]
            $keys.Count | Should -Be 1
        }

        It 'returns no keys for a check id with no entry' {
            $state = Get-MuteState -StateDir $script:stateDir
            $keys = Get-MutedFindingKey -State $state -CheckId 'network-listeners'
            , $keys | Should -BeOfType [string[]]
            $keys.Count | Should -Be 0
        }
    }

    Context 'reading while another process holds the file' {
        BeforeEach {
            New-Item -ItemType Directory -Path $script:stateDir | Out-Null
            Set-Content -LiteralPath $script:mutesPath -Value $script:ExampleJson -Encoding utf8
        }

        It 'reads while another handle holds the file with ReadWrite' {
            $holder = [System.IO.File]::Open($script:mutesPath, 'Open', 'ReadWrite', 'ReadWrite')
            try {
                $state = Get-MuteState -StateDir $script:stateDir -WarningVariable warned -WarningAction SilentlyContinue
            } finally {
                $holder.Dispose()
            }
            $warned | Should -BeNullOrEmpty
            $keys = Get-MutedFindingKey -State $state -CheckId 'startup-items'
            $keys | Should -Be @('startup:7eef5f7d094fe8c0')
        }

        It 'reads while another handle holds delete access, as a replacing writer does' {
            $holder = [System.IO.FileStream]::new($script:mutesPath, 'Open', 'ReadWrite',
                [System.IO.FileShare]'ReadWrite, Delete', 4096, [System.IO.FileOptions]::DeleteOnClose)
            try {
                $state = Get-MuteState -StateDir $script:stateDir -WarningVariable warned -WarningAction SilentlyContinue
            } finally {
                $holder.Dispose()
            }
            $warned | Should -BeNullOrEmpty
            $keys = Get-MutedFindingKey -State $state -CheckId 'startup-items'
            $keys | Should -Be @('startup:7eef5f7d094fe8c0')
        }
    }

    Context 'nothing to read' {
        It 'returns no keys, creates nothing and migrates nothing with no state folder and a checked TODO.md' {
            Set-Content -LiteralPath (Join-Path $script:base 'TODO.md') -Encoding utf8 `
                -Value "- [x] Enable Clear-TempFiles`n- [x] Restart-StoppedService"
            $before = @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Force | ForEach-Object FullName | Sort-Object)

            $state = Get-MuteState -StateDir $script:stateDir
            $keys = Get-MutedFindingKey -State $state -CheckId 'startup-items'

            $keys.Count | Should -Be 0
            $after = @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Force | ForEach-Object FullName | Sort-Object)
            $after | Should -Be $before
            Test-Path -LiteralPath $script:stateDir | Should -BeFalse
        }

        It 'returns no keys for an empty mutes.json' {
            New-Item -ItemType Directory -Path $script:stateDir | Out-Null
            Set-Content -LiteralPath $script:mutesPath -Value '' -Encoding utf8
            $state = Get-MuteState -StateDir $script:stateDir
            (Get-MutedFindingKey -State $state -CheckId 'startup-items').Count | Should -Be 0
        }

        It 'returns no keys for a null state' {
            (Get-MutedFindingKey -State $null -CheckId 'startup-items').Count | Should -Be 0
        }
    }

    Context 'a broken mutes.json' {
        BeforeEach {
            New-Item -ItemType Directory -Path $script:stateDir | Out-Null
        }

        It 'warns and returns no keys for <Case>' -ForEach @(
            @{ Case = 'malformed JSON'; Json = '{ "schema_version": "1.0", "checks": ' }
            @{ Case = 'a schema violation'; Json = '{ "schema_version": "1.0", "checks": { "startup-items": { "muted_findings": [ { "key": "startup:7eef5f7d094fe8c0" } ] } } }' }
            @{ Case = 'an unsupported schema_version'; Json = '{ "schema_version": "2.0", "checks": {} }' }
        ) {
            Set-Content -LiteralPath $script:mutesPath -Value $Json -Encoding utf8
            $state = Get-MuteState -StateDir $script:stateDir -WarningVariable warned -WarningAction SilentlyContinue
            $warned | Should -Not -BeNullOrEmpty
            (Get-MutedFindingKey -State $state -CheckId 'startup-items').Count | Should -Be 0
        }

        It 'never writes the broken file or a log beside it' {
            Set-Content -LiteralPath $script:mutesPath -Value '{ broken' -Encoding utf8
            $before = Get-FileHash -LiteralPath $script:mutesPath
            $null = Get-MuteState -StateDir $script:stateDir -WarningAction SilentlyContinue
            (Get-FileHash -LiteralPath $script:mutesPath).Hash | Should -Be $before.Hash
            @(Get-ChildItem -LiteralPath $script:stateDir -Force).Count | Should -Be 1
        }
    }
}
