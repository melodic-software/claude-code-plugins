#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/New-ElevatedLaunch.ps1 (New-, Get- and Start-ElevatedLaunch,
Get-ElevatedPassManifest) and the Invoke-ElevatedBootstrap.ps1 functions it writes into
the launcher. The launch string runs here exactly as the elevated pass runs it, one
string through Start-Process -ArgumentList into pwsh, minus -Verb RunAs, against a stub
orchestrator that prints the parameters it received. A launch that gets past the
manifest check needs the admin token for its staging folder, so those cases run only
elevated; the same path runs unelevated through the bootstrap's staging-folder seam.
#>

BeforeDiscovery {
    . "$PSScriptRoot\..\..\..\scripts\windows\lib\Test-IsElevated.ps1"
    $script:Elevated = Test-IsElevated
}

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'New-ElevatedLaunch.ps1', 'Write-ElevatedResult.ps1', 'Import-ElevatedResult.ps1'

    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:SavedOneDrive = $env:OneDrive
    # The session token of an administrator under UAC; a case below overrides it.
    Mock Get-TokenElevationType { 'Limited' }

    # Run the launch string in a child pwsh; returns its exit code, its stderr and the
    # parameters the stub orchestrator wrote to bound.json (UTF-8, so no console code page
    # alters them), or $null when the stub did not run.
    function Invoke-LaunchString {
        param([string] $ArgumentString, [string] $WorkDir, [string] $BoundPath)
        $stdout = Join-Path $WorkDir "stdout-$([guid]::NewGuid()).txt"
        $stderr = Join-Path $WorkDir "stderr-$([guid]::NewGuid()).txt"
        $process = Start-Process -FilePath $script:Pwsh -ArgumentList $ArgumentString -NoNewWindow -PassThru `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        if (-not $process.WaitForExit(60000)) {
            $process.Kill($true)
            throw 'The launch string did not finish within 60 s.'
        }
        $bound = if (Test-Path -LiteralPath $BoundPath) { Get-Content -LiteralPath $BoundPath -Raw -Encoding utf8 | ConvertFrom-Json }
        return [pscustomobject]@{ ExitCode = $process.ExitCode; Bound = $bound; Stderr = Get-Content -LiteralPath $stderr -Raw }
    }

    # A skill root holding a stub orchestrator, which writes what it received to -BoundPath
    # (outside the root, since the elevated run executes a copy it then removes), and one lib script.
    function New-StubSkillRoot {
        param([string] $Root, [string] $BoundPath)
        $skillRoot = Join-Path $Root 'skill root'
        $windows = Join-Path $skillRoot 'scripts\windows'
        New-Item -ItemType Directory -Path (Join-Path $windows 'lib') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $windows 'Invoke-MachineHealthCheck.ps1') -Encoding utf8 -Value (@'
param($OutputBase, $StateBase, $RunMode, [switch] $SkipBanner, $ResultPath, $ResultFileId)
[pscustomobject]@{
    OutputBase = $OutputBase; StateBase = $StateBase; RunMode = $RunMode; SkipBanner = $SkipBanner.IsPresent
    ResultPath = $ResultPath; ResultFileId = $ResultFileId; ScriptRoot = $PSScriptRoot; PSModulePath = $env:PSModulePath
} | ConvertTo-Json -Compress | Set-Content -LiteralPath '<bound>' -Encoding utf8
exit 5
'@).Replace('<bound>', $BoundPath)
        Set-Content -LiteralPath (Join-Path $windows 'lib\Stub-Lib.ps1') -Encoding utf8 -Value 'function Get-Stub { 1 }'
        return $skillRoot
    }
}

AfterAll {
    $env:OneDrive = $script:SavedOneDrive
}

Describe 'New-ElevatedLaunch' -Tag 'lib' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:work = Join-Path $root 'work'
        New-Item -ItemType Directory -Path $script:work | Out-Null
        $script:boundPath = Join-Path $script:work 'bound.json'
        $script:skillRoot = New-StubSkillRoot -Root $root -BoundPath $script:boundPath
        $script:libPath = Join-Path $script:skillRoot 'scripts\windows\lib\Stub-Lib.ps1'
        # Characters PowerShell would read as code outside a single-quoted literal.
        $script:root = $root
        $script:stateBase = Join-Path $root ('state base $x;&(%)' + [char]96 + 'n')
        $script:outputBase = Join-Path $root 'reports out; $(1)'
    }

    It 'pre-creates an empty result file under logs and returns an ID Write-ElevatedResult accepts' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ResultPath.StartsWith("$script:stateBase\logs\elevated-result-") | Should -BeTrue
        (Split-Path -Leaf $launch.ResultPath) | Should -Match '^elevated-result-\d{4}-\d{2}-\d{2}T\d{9}Z\.json$'
        (Get-Item -LiteralPath $launch.ResultPath).Length | Should -Be 0
        Test-FileIdFormat $launch.ResultFileId | Should -BeTrue
        { Write-ElevatedResult -Path $launch.ResultPath -FileId $launch.ResultFileId -Results @() } | Should -Not -Throw
        { Write-ElevatedResult -Path $launch.ResultPath -FileId '0000000000000000-00000000000000000000000000000000' -Results @() } |
            Should -Throw '*file ID*'
    }

    It 'writes the launcher without a byte order mark, its SHA-256 the returned hash' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ScriptSha256 | Should -BeExactly (Get-FileHash -LiteralPath $launch.ScriptPath -Algorithm SHA256).Hash
        (Split-Path -Leaf $launch.ScriptPath) | Should -Match '^elevated-run-\d{4}-\d{2}-\d{2}T\d{9}Z\.ps1$'
        $bytes = [System.IO.File]::ReadAllBytes($launch.ScriptPath)
        $bytes[0] | Should -Be ([byte][char]'f')
        [System.Text.Encoding]::UTF8.GetString($bytes) | Should -Not -Match 'DryRun|Transcript'
    }

    It 'writes the bootstrap functions, then one bootstrap call whose every argument is a constant and whose manifest hashes the skill files' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $ast = [scriptblock]::Create([System.IO.File]::ReadAllText($launch.ScriptPath)).Ast
        $statements = @($ast.EndBlock.Statements)
        $statements.Count | Should -Be 6
        @($statements[0..4] | ForEach-Object Name) | Should -Be @('Test-ElevatedPassPath', 'Get-SystemEnvironmentVariable',
            'Get-ElevatedPassEnvironment', 'New-ElevatedStagingFolder', 'Invoke-ElevatedBootstrap')
        $statements[5] | Should -BeOfType ([System.Management.Automation.Language.ExitStatementAst])
        $commands = @($statements[5].FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true))
        $commands.Count | Should -Be 1
        $elements = @($commands[0].CommandElements)
        $elements[0].Value | Should -BeExactly 'Invoke-ElevatedBootstrap'
        $bound = @{}
        for ($i = 1; $i -lt $elements.Count; $i += 2) {
            $elements[$i] | Should -BeOfType ([System.Management.Automation.Language.CommandParameterAst])
            $bound[$elements[$i].ParameterName] = $elements[$i + 1]
        }
        @($bound.Keys | Sort-Object) | Should -Be @('Manifest', 'OutputBase', 'ResultFileId', 'ResultPath', 'SourceRoot', 'StateBase')
        foreach ($name in 'OutputBase', 'ResultFileId', 'ResultPath', 'SourceRoot', 'StateBase') {
            $bound[$name].StringConstantType | Should -Be 'SingleQuoted'
        }
        $bound.SourceRoot.Value | Should -BeExactly $script:skillRoot
        $bound.StateBase.Value | Should -BeExactly $script:stateBase
        $bound.OutputBase.Value | Should -BeExactly $script:outputBase
        $bound.ResultPath.Value | Should -BeExactly $launch.ResultPath
        $bound.ResultFileId.Value | Should -BeExactly $launch.ResultFileId

        $written = @{}
        foreach ($pair in $bound.Manifest.KeyValuePairs) {
            $value = $pair.Item2.PipelineElements[0].Expression
            $pair.Item1.StringConstantType | Should -Be 'SingleQuoted'
            $value.StringConstantType | Should -Be 'SingleQuoted'
            $written[$pair.Item1.Value] = $value.Value
        }
        @($written.Keys | Sort-Object) | Should -Be @('scripts\windows\Invoke-MachineHealthCheck.ps1', 'scripts\windows\lib\Stub-Lib.ps1')
        foreach ($relative in $written.Keys) {
            $written[$relative] | Should -BeExactly (Get-FileHash -LiteralPath (Join-Path $script:skillRoot $relative) -Algorithm SHA256).Hash
        }
    }

    It 'builds an argument string whose block is the hash check, then the run of the same bytes' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $launch.ArgumentString | Should -Match '^-NoProfile -Command "[^"]*"$'
        $block = $launch.ArgumentString.Substring('-NoProfile -Command "'.Length).TrimEnd('"')
        $ast = [scriptblock]::Create($block).Ast
        $statements = @($ast.EndBlock.Statements)
        $statements.Count | Should -Be 4
        $statements[0].Extent.Text | Should -BeExactly "`$b = [IO.File]::ReadAllBytes('$($launch.ScriptPath)')"
        $statements[1].Extent.Text | Should -BeLike "if (*-cne '$($launch.ScriptSha256)') { exit 3 }"
        $statements[2].Extent.Text | Should -BeExactly '& ([scriptblock]::Create([Text.UTF8Encoding]::new($false).GetString($b)))'
        $statements[3].Extent.Text | Should -BeExactly 'exit $LASTEXITCODE'
    }

    It 'round-trips the paths through Start-Process and pwsh -Command, runs a removed copy and returns the orchestrator''s exit code' -Skip:(-not $script:Elevated) {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 5
        $run.Bound.StateBase | Should -BeExactly $script:stateBase
        $run.Bound.OutputBase | Should -BeExactly $script:outputBase
        $run.Bound.ResultPath | Should -BeExactly $launch.ResultPath
        $run.Bound.ResultFileId | Should -BeExactly $launch.ResultFileId
        $run.Bound.RunMode | Should -BeExactly 'on-demand'
        $run.Bound.SkipBanner | Should -BeTrue
        $run.Bound.ScriptRoot | Should -BeLike "$([Environment]::GetFolderPath('CommonApplicationData'))\machine-health-elevated-*"
        Test-Path -LiteralPath $run.Bound.ScriptRoot | Should -BeFalse
    }

    It 'exits 4 without running the orchestrator when <Case> after prepare' -ForEach @(
        @{ Case = 'a lib script changed'; Remove = $false }
        @{ Case = 'a lib script was removed'; Remove = $true }
    ) {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot
        if ($Remove) {
            Remove-Item -LiteralPath $script:libPath
        } else {
            Add-Content -LiteralPath $script:libPath -Value '# changed after prepare'
        }

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 4
        $run.Bound | Should -BeNullOrEmpty
        $run.Stderr | Should -BeLike '*refused*Stub-Lib.ps1*'
    }

    It 'exits 3 without running the script when it was edited after the hash' {
        $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot
        Add-Content -LiteralPath $launch.ScriptPath -Value '; ''tampered''' -NoNewline

        $run = Invoke-LaunchString -ArgumentString $launch.ArgumentString -WorkDir $script:work -BoundPath $script:boundPath

        $run.ExitCode | Should -Be 3
        $run.Bound | Should -BeNullOrEmpty
        Test-Path -LiteralPath $script:boundPath | Should -BeFalse
    }

    It 'refuses a <Case> in the <Which> and creates nothing' -ForEach @(
        @{ Case = 'right single quote'; Which = 'StateBase'; Char = [char]0x2019 }
        @{ Case = 'left single quote'; Which = 'StateBase'; Char = [char]0x2018 }
        @{ Case = 'low single quote'; Which = 'OutputBase'; Char = [char]0x201A }
        @{ Case = 'reversed single quote'; Which = 'OutputBase'; Char = [char]0x201B }
        @{ Case = 'apostrophe'; Which = 'StateBase'; Char = [char]0x27 }
        @{ Case = 'control character'; Which = 'StateBase'; Char = [char]0x1F }
    ) {
        $bad = Join-Path $script:root "st$($Char)); Write-Output INJECTED; #"
        $state = if ($Which -eq 'StateBase') { $bad } else { $script:stateBase }
        $output = if ($Which -eq 'OutputBase') { $bad } else { $script:outputBase }

        { New-ElevatedLaunch -OutputBase $output -StateBase $state -SkillRoot $script:skillRoot } |
            Should -Throw '*control character or a single quote*'
        Test-Path -LiteralPath $state | Should -BeFalse
    }

    It 'refuses a skill root holding a single quote' {
        $quotedRoot = Join-Path $script:root "skill$([char]0x2019)root"
        New-Item -ItemType Directory -Path (Join-Path $quotedRoot 'scripts\windows') | Out-Null
        Copy-Item -LiteralPath (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') `
            -Destination (Join-Path $quotedRoot 'scripts\windows')

        { New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $quotedRoot } |
            Should -Throw '*single quote*'
    }

    It 'stamps the file names with the Gregorian UTC year under a culture with another calendar' {
        $saved = [cultureinfo]::CurrentCulture
        [cultureinfo]::CurrentCulture = 'th-TH'
        try {
            $launch = New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot
        } finally {
            [cultureinfo]::CurrentCulture = $saved
        }

        $year = (Get-Date).ToUniversalTime().Year
        (Split-Path -Leaf $launch.ResultPath) | Should -BeLike "elevated-result-$year-*"
        (Split-Path -Leaf $launch.ScriptPath) | Should -BeLike "elevated-run-$year-*"
    }

    It 'refuses a session token with a <Type> elevation type and creates nothing' -ForEach @(
        @{ Type = 'Default' }
        @{ Type = 'Full' }
    ) {
        Mock Get-TokenElevationType { $Type }

        { New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot } |
            Should -Throw "*elevation type is $Type*"
        Test-Path -LiteralPath $script:stateBase | Should -BeFalse
    }

    It 'refuses a state folder under a OneDrive root and creates nothing there' {
        $env:OneDrive = Split-Path -Parent $script:stateBase
        try {
            { New-ElevatedLaunch -OutputBase $script:outputBase -StateBase $script:stateBase -SkillRoot $script:skillRoot } |
                Should -Throw '*cloud sync root*'
        } finally {
            $env:OneDrive = $script:SavedOneDrive
        }
        Test-Path -LiteralPath $script:stateBase | Should -BeFalse
    }
}

Describe 'Get-ElevatedLaunch' -Tag 'lib' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:skillRoot = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path (Join-Path $script:skillRoot 'scripts\windows') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') -Value 'param()'
        $script:stateBase = Join-Path $root 'state'
        $script:launch = New-ElevatedLaunch -OutputBase (Join-Path $root 'out') -StateBase $script:stateBase -SkillRoot $script:skillRoot
    }

    It 'rebuilds the New-ElevatedLaunch record from the state root and the shown hash' {
        $found = Get-ElevatedLaunch -StateBase $script:stateBase -ScriptSha256 $script:launch.ScriptSha256

        foreach ($name in 'ScriptPath', 'ScriptSha256', 'ResultPath', 'ResultFileId', 'ArgumentString') {
            $found.$name | Should -BeExactly $script:launch.$name
        }
    }

    It 'refuses a script whose name carries another stamp than its result path' {
        $renamed = Join-Path (Split-Path -Parent $script:launch.ScriptPath) 'elevated-run-2000-01-01T000000000Z.ps1'
        Move-Item -LiteralPath $script:launch.ScriptPath -Destination $renamed

        { Get-ElevatedLaunch -StateBase $script:stateBase -ScriptSha256 $script:launch.ScriptSha256 } |
            Should -Throw '*elevated-result-2000-01-01T000000000Z.json*'
    }

    It 'finds nothing once the script no longer hashes to the shown value' {
        Add-Content -LiteralPath $script:launch.ScriptPath -Value ' ' -NoNewline

        { Get-ElevatedLaunch -StateBase $script:stateBase -ScriptSha256 $script:launch.ScriptSha256 } |
            Should -Throw '*No elevated-run script*'
    }
}

Describe 'Start-ElevatedLaunch' -Tag 'lib' {
    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:skillRoot = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path (Join-Path $script:skillRoot 'scripts\windows') | Out-Null
        Set-Content -LiteralPath (Join-Path $script:skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') -Value 'param()'
        $script:launch = New-ElevatedLaunch -OutputBase (Join-Path $root 'out') -StateBase (Join-Path $root 'state') `
            -SkillRoot $script:skillRoot
        $script:received = [System.Collections.Generic.List[string]]::new()
        $script:receivedFile = [System.Collections.Generic.List[string]]::new()
        $script:fakeLauncher = { param($FilePath, $ArgumentString)
            $script:receivedFile.Add($FilePath); $script:received.Add($ArgumentString); 7 }
    }

    It 'hands the launcher this session''s own pwsh and the record''s exact argument string, and returns its exit code' {
        $code = Start-ElevatedLaunch -Launch $script:launch -Launcher $script:fakeLauncher

        $code | Should -Be 7
        @($script:received) | Should -Be @($script:launch.ArgumentString)
        @($script:receivedFile) | Should -Be @($script:Pwsh)
    }

    It 'refuses a record whose argument string was changed' {
        $tampered = $script:launch.PSObject.Copy()
        $tampered.ArgumentString = $tampered.ArgumentString.Replace('exit 3', 'exit 0')

        { Start-ElevatedLaunch -Launch $tampered -Launcher $script:fakeLauncher } | Should -Throw '*Refused*'
        $script:received.Count | Should -Be 0
    }
}

Describe 'Get-ElevatedPassManifest' -Tag 'lib' {
    It 'hashes the orchestrator, the lib and check scripts, the catalog and its schemas, and nothing else' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $listed = 'scripts\windows\Invoke-MachineHealthCheck.ps1', 'scripts\windows\lib\A.ps1', 'scripts\windows\checks\Test-B.ps1',
        'catalog\checks.jsonc', 'catalog\schemas\mutes.schema.json'
        $unlisted = 'scripts\windows\Format-ShortReport.ps1', 'scripts\windows\lib\notes.md', 'scripts\windows\lib\A.ps1xml',
        'catalog\cisa-kev.json'
        foreach ($relative in $listed + $unlisted) {
            $path = Join-Path $root $relative
            New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $relative
        }
        # A hidden lib script still loads, so it is still listed.
        $hidden = Get-Item -LiteralPath (Join-Path $root 'scripts\windows\lib\A.ps1')
        $hidden.Attributes = $hidden.Attributes -bor [System.IO.FileAttributes]::Hidden

        $manifest = Get-ElevatedPassManifest -SkillRoot $root

        @($manifest.Keys | Sort-Object) | Should -Be @($listed | Sort-Object)
        foreach ($relative in $listed) {
            $manifest[$relative] | Should -BeExactly (Get-FileHash -LiteralPath (Join-Path $root $relative) -Algorithm SHA256).Hash
        }
    }

    It 'refuses a listed file whose name the bootstrap would refuse' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        New-Item -ItemType Directory -Path (Join-Path $root 'scripts\windows\lib') | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'scripts\windows\lib\Stray copy.ps1') -Value 'x'

        { Get-ElevatedPassManifest -SkillRoot $root } | Should -Throw '*Stray copy.ps1*'
    }
}

Describe 'Get-ElevatedPassEnvironment' -Tag 'lib' {
    It 'gives each HKCU\Environment name its system value, removes one the system lacks, and pins PSModulePath' {
        $pinned = Get-ElevatedPassEnvironment -UserVariableName 'Path', 'TEMP', 'OneDrive', 'PSModulePath' -SystemVariable @{
            Path         = 'C:\Windows\system32;C:\Windows'
            TEMP         = 'C:\Windows\TEMP'
            PSModulePath = 'C:\Program Files\WindowsPowerShell\Modules;C:\Program Files\PowerShell\Modules\;C:\Windows\system32\WindowsPowerShell\v1.0\Modules'
        } -PSHomePath 'C:\Program Files\PowerShell\7' -ProgramFilesPath 'C:\Program Files'

        $pinned['Path'] | Should -BeExactly 'C:\Windows\system32;C:\Windows'
        $pinned['TEMP'] | Should -BeExactly 'C:\Windows\TEMP'
        $pinned.Contains('OneDrive') | Should -BeTrue
        $pinned['OneDrive'] | Should -BeNullOrEmpty
        @($pinned['PSModulePath'] -split ';') | Should -Be @(
            'C:\Program Files\PowerShell\Modules'
            'C:\Program Files\PowerShell\7\Modules'
            'C:\Program Files\WindowsPowerShell\Modules'
            'C:\Windows\system32\WindowsPowerShell\v1.0\Modules')
    }

    It 'pins Path and PSModulePath when HKCU\Environment sets nothing' {
        $pinned = Get-ElevatedPassEnvironment -UserVariableName @() -SystemVariable @{ Path = 'C:\Windows\system32' } `
            -PSHomePath 'C:\pwsh' -ProgramFilesPath 'C:\PF'

        @($pinned.Keys) | Should -Be @('Path', 'PSModulePath')
        $pinned['Path'] | Should -BeExactly 'C:\Windows\system32'
        $pinned['PSModulePath'] | Should -BeExactly 'C:\PF\PowerShell\Modules;C:\pwsh\Modules'
    }
}

Describe 'Get-SystemEnvironmentVariable' -Tag 'lib' {
    It 'returns the system Path' {
        (Get-SystemEnvironmentVariable)['Path'] | Should -BeLike "*$([Environment]::SystemDirectory)*"
    }
}

Describe 'Invoke-ElevatedBootstrap' -Tag 'lib' {
    BeforeAll {
        # Runs the bootstrap in its own pwsh, since it rewrites that process's environment, with the
        # staging-folder seam: a plain folder under -StagingParent in place of the admin-only one.
        $script:runner = Join-Path $TestDrive 'run-bootstrap.ps1'
        Set-Content -LiteralPath $script:runner -Encoding utf8 -Value @'
param([string] $LibRoot, [string] $SkillRoot, [string] $StagingParent, [string] $ChangeAfterManifest)
. (Join-Path $LibRoot 'New-ElevatedLaunch.ps1')
$manifest = Get-ElevatedPassManifest -SkillRoot $SkillRoot
if ($ChangeAfterManifest) { [System.IO.File]::AppendAllText($ChangeAfterManifest, '# changed after the manifest') }
exit (Invoke-ElevatedBootstrap -SourceRoot $SkillRoot -Manifest $manifest -OutputBase 'C:\out' -StateBase 'C:\state' `
        -ResultPath 'C:\state\logs\result.json' -ResultFileId 'file-id' -NewStagingFolder {
        $path = Join-Path $StagingParent ([guid]::NewGuid().ToString('N'))
        [void][System.IO.Directory]::CreateDirectory($path)
        $path
    })
'@
    }

    BeforeEach {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $script:staging = Join-Path $root 'staging'
        New-Item -ItemType Directory -Path $script:staging | Out-Null
        $script:boundPath = Join-Path $root 'bound.json'
        $script:skillRoot = New-StubSkillRoot -Root $root -BoundPath $script:boundPath
    }

    It 'runs the orchestrator from a copy, under machine-wide module folders only, and removes the copy' {
        & $script:Pwsh -NoProfile -NonInteractive -File $script:runner -LibRoot $script:LibRoot -SkillRoot $script:skillRoot `
            -StagingParent $script:staging 2>$null | Out-Null

        $LASTEXITCODE | Should -Be 5
        $bound = Get-Content -LiteralPath $script:boundPath -Raw -Encoding utf8 | ConvertFrom-Json
        $bound.ScriptRoot | Should -BeLike "$script:staging\*\scripts\windows"
        $bound.ResultPath | Should -BeExactly 'C:\state\logs\result.json'
        $bound.ResultFileId | Should -BeExactly 'file-id'
        $folders = @($bound.PSModulePath -split ';')
        $folders | Should -Contain (Join-Path $PSHOME 'Modules')
        $folders | Should -Not -Contain (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\Modules')
        @(Get-ChildItem -LiteralPath $script:staging -Force) | Should -BeNullOrEmpty
    }

    It 'refuses a lib script changed after the manifest was built, copying and running nothing' {
        $lib = Join-Path $script:skillRoot 'scripts\windows\lib\Stub-Lib.ps1'
        & $script:Pwsh -NoProfile -NonInteractive -File $script:runner -LibRoot $script:LibRoot -SkillRoot $script:skillRoot `
            -StagingParent $script:staging -ChangeAfterManifest $lib 2>$null | Out-Null

        $LASTEXITCODE | Should -Be 4
        Test-Path -LiteralPath $script:boundPath | Should -BeFalse
        @(Get-ChildItem -LiteralPath $script:staging -Force) | Should -BeNullOrEmpty
    }
}

Describe 'Elevated pass round trip' -Tag 'lib' {
    It 'imports what the elevated side wrote into the file New-ElevatedLaunch prepared' {
        $root = Join-Path $TestDrive ([guid]::NewGuid())
        $skillRoot = Join-Path $root 'skill'
        New-Item -ItemType Directory -Path (Join-Path $skillRoot 'scripts\windows') | Out-Null
        Set-Content -LiteralPath (Join-Path $skillRoot 'scripts\windows\Invoke-MachineHealthCheck.ps1') -Value 'param()'
        $launch = New-ElevatedLaunch -OutputBase (Join-Path $root 'out') -StateBase (Join-Path $root 'state') -SkillRoot $skillRoot
        $result = { param($Id, $Severity, $Summary) [pscustomobject]@{
                id = $Id; category = 'storage'; os = 'windows'; ran_at = (Get-Date).ToString('o'); severity = $Severity
                summary = $Summary; detail = @{}; commands = @(); needs_admin = $true; ran_successfully = $true
                duration_ms = 1; trend = $null; notes = $null; error = $null
            } }
        Start-Sleep -Milliseconds 20

        # -Elevated $true stands in for the admin token.
        Write-ElevatedResult -Path $launch.ResultPath -FileId $launch.ResultFileId -Elevated $true `
            -Results @(& $result 'disk-space' 'WARN' 'elevated reading') -Log @('check_ok id=disk-space')
        $import = Import-ElevatedResult -Path $launch.ResultPath -CheckResults @(& $result 'disk-space' 'UNKNOWN' 'standard reading')

        $import.Rejected | Should -BeNullOrEmpty
        @($import.ElevatedChecks) | Should -Be @('disk-space')
        $import.Results[0].summary | Should -BeExactly 'elevated reading'
        @($import.Log) | Should -Be @('check_ok id=disk-space')
    }
}
