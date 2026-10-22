#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Write-ElevatedResult.ps1 and the orchestrator's
-ResultPath branch that calls it. The document shape and the refusal rules come
from reference/windows/elevation-matrix.md, "How to run elevated".
#>

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript @(
        'Write-ElevatedResult.ps1', 'Assert-CheckResult.ps1', 'ConvertFrom-Jsonc.ps1')

    function Get-IdOf {
        param([string] $Path)
        $handle = Open-NoFollowFile -Path $Path
        try { (Get-FileIdentity -Handle $handle).FileId } finally { $handle.Dispose() }
    }

    # Every entry under $Root: relative name, size, creation time. Write times are
    # left out because filling the result file changes its write time by design.
    function Get-TreeListing {
        param([string] $Root)
        @(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $rel = $_.FullName.Substring($Root.Length)
                if ($_.PSIsContainer) { "$rel\" } else { "$rel|$($_.Length)|$($_.CreationTimeUtc.ToString('o'))" }
            })
    }

    $script:SampleResult = [pscustomobject]@{
        id = 'disk-space'; category = 'storage'; os = 'windows'; ran_at = '2026-10-21T00:00:00.0000000Z'
        severity = 'OK'; summary = 'All volumes healthy.'; detail = @{}; commands = @(); needs_admin = $true
        ran_successfully = $true; duration_ms = 5; trend = $null; notes = $null; error = $null
    }
}

Describe 'Write-ElevatedResult' -Tag 'lib' {
    BeforeEach {
        $script:dir = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:dir | Out-Null
        $script:path = Join-Path $script:dir 'elevated-result.json'
        [System.IO.File]::Create($script:path).Dispose()
        $script:id = Get-IdOf $script:path
    }

    It 'writes the document into the pre-created file, leaving its creation time and the folder listing alone' {
        $created = [System.IO.File]::GetCreationTimeUtc($script:path)
        $names = @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Force | ForEach-Object FullName | Sort-Object)

        Write-ElevatedResult -Path $script:path -FileId $script:id -Results @($script:SampleResult) `
            -Log @('line one') -Elevated $true

        $bytes = [System.IO.File]::ReadAllBytes($script:path)
        $bytes[0] | Should -Be 0x7B
        $doc = [System.Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json
        $doc.format | Should -BeExactly 'elevated-result/1'
        $doc.elevated | Should -BeTrue
        @($doc.results).Count | Should -Be 1
        $doc.results[0].id | Should -BeExactly 'disk-space'
        { Assert-CheckResult $doc.results[0] } | Should -Not -Throw
        @($doc.log) | Should -Be @('line one')
        ([DateTimeOffset]$doc.ran_at).UtcDateTime | Should -BeGreaterThan $created
        [System.IO.File]::GetCreationTimeUtc($script:path) | Should -Be $created
        @(Get-ChildItem -LiteralPath $TestDrive -Recurse -Force | ForEach-Object FullName | Sort-Object) | Should -Be $names
    }

    It 'replaces longer earlier content instead of leaving a tail of it' {
        Set-Content -LiteralPath $script:path -Value ('x' * 5000) -NoNewline

        Write-ElevatedResult -Path $script:path -FileId $script:id -Results @() -Log @() -Elevated $false

        $doc = Get-Content -LiteralPath $script:path -Raw | ConvertFrom-Json
        $doc.format | Should -BeExactly 'elevated-result/1'
        @($doc.results).Count | Should -Be 0
    }

    It 'refuses a file whose ID differs, as after a delete and recreate, and writes nothing' {
        Remove-Item -LiteralPath $script:path
        [System.IO.File]::Create($script:path).Dispose()

        { Write-ElevatedResult -Path $script:path -FileId $script:id -Results @($script:SampleResult) } |
            Should -Throw '*file ID*'
        (Get-Item -LiteralPath $script:path).Length | Should -Be 0
    }

    It 'refuses a hard link swapped in at the path and leaves the linked file unchanged' {
        $other = Join-Path $script:dir 'other.json'
        Set-Content -LiteralPath $other -Value 'original' -NoNewline
        Remove-Item -LiteralPath $script:path
        New-Item -ItemType HardLink -Path $script:path -Target $other | Out-Null

        { Write-ElevatedResult -Path $script:path -FileId $script:id -Results @($script:SampleResult) } |
            Should -Throw '*file ID*'
        Get-Content -LiteralPath $other -Raw | Should -BeExactly 'original'
    }

    It 'refuses a symbolic link swapped in at the path without writing through it' {
        $target = Join-Path $script:dir 'target.json'
        Set-Content -LiteralPath $target -Value 'original' -NoNewline
        Remove-Item -LiteralPath $script:path
        New-Item -ItemType SymbolicLink -Path $script:path -Target $target | Out-Null

        { Write-ElevatedResult -Path $script:path -FileId $script:id -Results @($script:SampleResult) } |
            Should -Throw '*reparse point*'
        Get-Content -LiteralPath $target -Raw | Should -BeExactly 'original'
    }

    It 'refuses a junction swapped in at the path without writing into its target' {
        $targetDir = Join-Path $script:dir 'elsewhere'
        New-Item -ItemType Directory -Path $targetDir | Out-Null
        Remove-Item -LiteralPath $script:path
        New-Item -ItemType Junction -Path $script:path -Target $targetDir | Out-Null

        { Write-ElevatedResult -Path $script:path -FileId $script:id -Results @($script:SampleResult) } | Should -Throw
        @(Get-ChildItem -LiteralPath $targetDir -Force).Count | Should -Be 0
    }

    It 'refuses a junction swapped in for the parent folder without writing into the same-named file it reaches' {
        # Only the last path component is opened without following reparse points; a
        # junction higher up is followed, so the file ID check is what refuses this.
        $elsewhere = Join-Path $TestDrive "elsewhere-$([guid]::NewGuid())"
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        $decoy = Join-Path $elsewhere 'elevated-result.json'
        Set-Content -LiteralPath $decoy -Value 'original' -NoNewline
        Remove-Item -LiteralPath $script:dir -Recurse
        New-Item -ItemType Junction -Path $script:dir -Target $elsewhere | Out-Null

        { Write-ElevatedResult -Path $script:path -FileId $script:id -Results @($script:SampleResult) } |
            Should -Throw '*file ID*'
        Get-Content -LiteralPath $decoy -Raw | Should -BeExactly 'original'
    }

    It 'refuses a missing file and creates none' {
        Remove-Item -LiteralPath $script:path

        { Write-ElevatedResult -Path $script:path -FileId $script:id -Results @() } | Should -Throw
        Test-Path -LiteralPath $script:path | Should -BeFalse
    }
}

Describe 'Invoke-MachineHealthCheck -ResultPath' -Tag 'orchestrator' {
    BeforeAll {
        $script:Orchestrator = Join-Path $script:SkillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1'
        $catalog = Get-Content -LiteralPath (Join-Path $script:SkillRoot 'catalog\checks.jsonc') -Raw | ConvertFrom-Jsonc
        $script:QuietOverlay = @{ checks = @($catalog.checks | ForEach-Object { @{ id = $_.id; enabled = $false } }) } |
            ConvertTo-Json -Depth 5
    }

    BeforeEach {
        # A StateBase with no state folder and no mutes.json, a proposals file holding a
        # checked approval the approvals migration would read, an overlay that switches
        # every check off, and the pre-created result file.
        $script:root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:stateBase = Join-Path $script:root 'state-base'
        $script:outputBase = Join-Path $script:root 'output'
        New-Item -ItemType Directory -Path (Join-Path $script:stateBase 'catalog'), (Join-Path $script:stateBase 'logs') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:stateBase 'catalog\checks.local.jsonc') -Value $script:QuietOverlay -Encoding utf8
        Set-Content -LiteralPath (Join-Path $script:stateBase 'TODO.md') -Value '- [x] Enable Clear-TempFiles' -Encoding utf8
        $script:resultPath = Join-Path $script:stateBase 'logs\elevated-result-test.json'
        [System.IO.File]::Create($script:resultPath).Dispose()
        $script:resultId = Get-IdOf $script:resultPath
    }

    It 'fills only the result file: the listing differs only in its length, with no state folder and TODO.md untouched' {
        $before = Get-TreeListing $script:stateBase

        & pwsh -NoProfile -NonInteractive -File $script:Orchestrator -OutputBase $script:outputBase `
            -StateBase $script:stateBase -RunMode on-demand -SkipBanner -ResultPath $script:resultPath `
            -ResultFileId $script:resultId 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 0

        $after = Get-TreeListing $script:stateBase
        $changed = @(Compare-Object $before $after | ForEach-Object { ($_.InputObject -split '\|')[0] } | Sort-Object -Unique)
        $changed | Should -Be @('\logs\elevated-result-test.json')
        ($before | Where-Object { $_ -like '\logs\elevated-result-test.json|*' }) | Should -BeLike '*|0|*'
        Test-Path -LiteralPath (Join-Path $script:stateBase 'state') | Should -BeFalse
        Get-Content -LiteralPath (Join-Path $script:stateBase 'TODO.md') -Raw | Should -BeLike '- `[x`] Enable Clear-TempFiles*'
        Test-Path -LiteralPath $script:outputBase | Should -BeFalse
        $doc = Get-Content -LiteralPath $script:resultPath -Raw | ConvertFrom-Json
        $doc.format | Should -BeExactly 'elevated-result/1'
        @($doc.results).Count | Should -Be 0
    }

    It 'exits 1 and writes nothing when the file ID does not match' {
        $before = Get-TreeListing $script:stateBase

        & pwsh -NoProfile -NonInteractive -File $script:Orchestrator -OutputBase $script:outputBase `
            -StateBase $script:stateBase -RunMode on-demand -SkipBanner -ResultPath $script:resultPath `
            -ResultFileId '00000000-0000000000000000' 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1

        Get-TreeListing $script:stateBase | Should -Be $before
    }

    It 'does not bind -DryRun together with -ResultPath' {
        & pwsh -NoProfile -NonInteractive -File $script:Orchestrator -OutputBase $script:outputBase `
            -StateBase $script:stateBase -SkipBanner -ResultPath $script:resultPath `
            -ResultFileId $script:resultId -DryRun 2>$null | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        (Get-Item -LiteralPath $script:resultPath).Length | Should -Be 0
    }
}
