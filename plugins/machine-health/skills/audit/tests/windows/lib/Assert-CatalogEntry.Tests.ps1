#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }
<#
.SYNOPSIS
Tests for scripts/windows/lib/Assert-CatalogEntry.ps1 and the catalog itself.

.DESCRIPTION
Assert-CatalogEntry pins the contract between catalog/checks.jsonc and the
orchestrator. The integration Describe block re-parses the real catalog file
so any drift between the schema and the shipped catalog fails CI.
#>

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:SkillRoot = Split-Path -Parent $script:TestsRoot
    $script:LibRoot = Join-Path $script:SkillRoot 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'ConvertFrom-Jsonc.ps1')
    . (Join-Path $script:LibRoot 'Assert-CatalogEntry.ps1')

    function New-ValidEntry {
        param([hashtable] $Overrides = @{})
        $base = [ordered]@{
            id               = 'disk-space'
            category         = 'storage'
            os               = @('windows')
            script           = 'scripts/windows/checks/Test-DiskHealth.ps1'
            severity_rules   = 'references/windows/check-catalog.md#2'
            needs_admin      = $false
            enabled          = $true
            deprecated       = $false
            added_on         = '2026-04-22'
            crash_count      = 0
            identical_streak = 0
        }
        foreach ($k in $Overrides.Keys) { $base[$k] = $Overrides[$k] }
        return [pscustomobject]$base
    }
}

Describe 'Assert-CatalogEntry' -Tag 'lib' {
    Context 'valid entries' {
        It 'accepts a minimal valid entry' {
            Assert-CatalogEntry (New-ValidEntry) | Should -BeTrue
        }

        It 'accepts a deprecated entry with a reason' {
            $entry = New-ValidEntry -Overrides @{
                deprecated         = $true
                deprecation_reason = 'replaced by Foo'
            }
            Assert-CatalogEntry $entry | Should -BeTrue
        }

        It 'accepts an entry targeting multiple operating systems' {
            $entry = New-ValidEntry -Overrides @{ os = @('windows', 'linux') }
            Assert-CatalogEntry $entry | Should -BeTrue
        }

        It 'accepts an entry with the cadence extension field' {
            $entry = New-ValidEntry -Overrides @{ cadence = 'monthly' }
            Assert-CatalogEntry $entry | Should -BeTrue
        }

        It 'accepts the config category (declared-configuration drift checks)' {
            $entry = New-ValidEntry -Overrides @{ category = 'config' }
            Assert-CatalogEntry $entry | Should -BeTrue
        }
    }

    Context 'invalid entries' {
        It 'rejects a missing required field' {
            $entry = [pscustomobject]@{ id = 'x' }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*missing required field*'
        }

        It 'rejects a non-kebab-case id' {
            $entry = New-ValidEntry -Overrides @{ id = 'DiskSpace' }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*kebab-case*'
        }

        It 'rejects an unknown category' {
            $entry = New-ValidEntry -Overrides @{ category = 'hairdryers' }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*category*not in allowed set*'
        }

        It 'rejects an empty os array' {
            $entry = New-ValidEntry -Overrides @{ os = @() }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*os list is empty*'
        }

        It 'rejects a non-windows/macos/linux os value' {
            $entry = New-ValidEntry -Overrides @{ os = @('bsd') }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage "*os 'bsd' not in allowed set*"
        }

        It 'rejects a script path outside the expected shape' {
            $entry = New-ValidEntry -Overrides @{ script = 'checks/foo.ps1' }
            { Assert-CatalogEntry $entry } |
                Should -Throw -ExpectedMessage '*scripts/<os>/checks/Name.ps1*'
        }

        It 'rejects a malformed added_on date' {
            $entry = New-ValidEntry -Overrides @{ added_on = 'April 2026' }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*ISO 8601 date*'
        }

        It 'rejects deprecated=true without a deprecation_reason' {
            $entry = New-ValidEntry -Overrides @{ deprecated = $true }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*no deprecation_reason*'
        }

        It 'rejects negative crash_count' {
            $entry = New-ValidEntry -Overrides @{ crash_count = -1 }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage '*crash_count is negative*'
        }

        It 'rejects an unknown cadence' {
            $entry = New-ValidEntry -Overrides @{ cadence = 'hourly' }
            { Assert-CatalogEntry $entry } | Should -Throw -ExpectedMessage "*cadence 'hourly' not in allowed set*"
        }
    }
}

Describe 'Catalog integration: catalog/checks.jsonc conforms to schema' -Tag 'integration' {
    BeforeAll {
        $script:CatalogPath = Join-Path $script:SkillRoot 'catalog\checks.jsonc'
        $script:Raw = Get-Content -LiteralPath $script:CatalogPath -Raw
        $script:Catalog = ConvertFrom-Jsonc -InputText $script:Raw
    }

    It 'parses the real catalog as JSONC' {
        $script:Catalog | Should -Not -BeNull
        $script:Catalog.checks | Should -Not -BeNull
        @($script:Catalog.checks).Count | Should -BeGreaterThan 0
    }

    It 'every entry passes Assert-CatalogEntry' {
        foreach ($entry in $script:Catalog.checks) {
            { Assert-CatalogEntry $entry -Because 'checks.jsonc integration test' } |
                Should -Not -Throw
        }
    }

    It 'every entry id is unique' {
        $ids = @($script:Catalog.checks | ForEach-Object { $_.id })
        $duplicates = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
        $duplicates | Should -BeNullOrEmpty
    }

    It 'every script path points to a file that exists on disk' {
        foreach ($entry in $script:Catalog.checks) {
            $expectedPath = Join-Path $script:SkillRoot $entry.script
            Test-Path -LiteralPath $expectedPath | Should -BeTrue -Because "$($entry.id) -> $expectedPath"
        }
    }
}

Describe 'Category vocabulary: schemas and validators agree' -Tag 'lib' {
    # The category enum lives in four places: checks.schema.json,
    # check-result.schema.json, Assert-CatalogEntry, and Assert-CheckResult.
    # A value present in a schema but missing from a validator silently
    # disables every check declaring it (the orchestrator skips entries
    # Assert-CatalogEntry rejects), and a value present in one validator but
    # not the other admits an overlay entry whose emitted result is then
    # rejected - so all four copies are compared exactly, in both directions:
    # the validators' literal $validCategories sets are extracted from the
    # AST and matched against the schema enums, and each schema value is also
    # accepted behaviorally.
    BeforeAll {
        . (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
        . (Join-Path $script:LibRoot 'Write-HealthResult.ps1')
        $schemasRoot = Join-Path $script:SkillRoot 'catalog\schemas'
        $checksSchema = Get-Content -LiteralPath (Join-Path $schemasRoot 'checks.schema.json') -Raw |
            ConvertFrom-Json
        $resultSchema = Get-Content -LiteralPath (Join-Path $schemasRoot 'check-result.schema.json') -Raw |
            ConvertFrom-Json
        $script:CatalogCategories = @($checksSchema.'$defs'.CheckEntry.properties.category.enum)
        $script:ResultCategories = @($resultSchema.properties.category.enum)

        function Get-ValidatorCategorySet {
            param([Parameter(Mandatory)] [string] $Path)
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Path, [ref]$null, [ref]$null)
            $assignments = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $node.Left.Extent.Text -eq '$validCategories'
                    }, $true))
            if ($assignments.Count -ne 1) {
                throw "Expected exactly one `$validCategories assignment in $Path, found $($assignments.Count)."
            }
            $right = $assignments[0].Right
            $expr = if ($right -is [System.Management.Automation.Language.PipelineAst]) {
                $right.GetPureExpression()
            } else {
                $right.Expression
            }
            @($expr.SafeGetValue())
        }
    }

    It 'the two schemas declare the same category set' {
        $script:CatalogCategories | Should -Be $script:ResultCategories
    }

    It 'Assert-CatalogEntry accepts exactly the schema-declared set (both directions)' {
        $validatorSet = Get-ValidatorCategorySet (Join-Path $script:LibRoot 'Assert-CatalogEntry.ps1')
        ($validatorSet | Sort-Object) | Should -Be ($script:CatalogCategories | Sort-Object)
    }

    It 'Assert-CheckResult accepts exactly the schema-declared set (both directions)' {
        $validatorSet = Get-ValidatorCategorySet (Join-Path $script:LibRoot 'Assert-CheckResult.ps1')
        ($validatorSet | Sort-Object) | Should -Be ($script:ResultCategories | Sort-Object)
    }

    It 'Assert-CatalogEntry accepts every schema-declared category' {
        $script:CatalogCategories.Count | Should -BeGreaterThan 0
        foreach ($cat in $script:CatalogCategories) {
            $entry = New-ValidEntry -Overrides @{ category = $cat }
            Assert-CatalogEntry $entry -Because "schema category '$cat'" | Should -BeTrue
        }
    }

    It 'Assert-CheckResult accepts every schema-declared category' {
        foreach ($cat in $script:ResultCategories) {
            $result = New-HealthResult -Id 'parity-probe' -Category $cat -Os 'windows' `
                -Severity 'OK' -Summary 'category parity probe'
            Assert-CheckResult $result -Because "schema category '$cat'" | Should -BeTrue
        }
    }
}
