#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    $script:TestsRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:LibRoot = Join-Path (Split-Path -Parent $script:TestsRoot) 'scripts\windows\lib'
    . (Join-Path $script:LibRoot 'Invoke-Discovery.ps1')

    function New-Probe {
        param(
            [string] $Dimension,
            [bool] $Detected,
            [string] $SuggestedCheckId,
            [string] $Rationale = 'test',
            [bool] $Straightforward = $true
        )
        [pscustomobject]@{
            dimension          = $Dimension
            detected           = $Detected
            suggested_check_id = $SuggestedCheckId
            rationale          = $Rationale
            straightforward    = $Straightforward
        }
    }

    function New-CatalogEntry {
        param([string] $Id)
        [pscustomobject]@{ id = $Id }
    }
}

Describe 'Invoke-Discovery' -Tag 'lib' {
    It 'returns no proposals when catalog already covers every detection' {
        $catalog = @(New-CatalogEntry 'docker-disk-usage')
        $probes = @(New-Probe -Dimension 'Docker Desktop' -Detected $true -SuggestedCheckId 'docker-disk-usage')

        $out = @(Invoke-Discovery -Catalog $catalog -ProbeResults $probes)
        $out.Count | Should -Be 0
    }

    It 'returns a proposal when detection is not in catalog' {
        $catalog = @()
        $probes = @(New-Probe -Dimension 'Docker Desktop' -Detected $true -SuggestedCheckId 'docker-disk-usage')

        $out = @(Invoke-Discovery -Catalog $catalog -ProbeResults $probes)
        $out.Count | Should -Be 1
        $out[0].dimension | Should -Be 'Docker Desktop'
    }

    It 'skips probes where nothing is detected' {
        $probes = @(New-Probe -Dimension 'Docker Desktop' -Detected $false -SuggestedCheckId 'docker-disk-usage')
        $out = @(Invoke-Discovery -Catalog @() -ProbeResults $probes)
        $out.Count | Should -Be 0
    }

    It 'caps proposals at MaxProposals' {
        $probes = @(
            New-Probe -Dimension 'A' -Detected $true -SuggestedCheckId 'a'
            New-Probe -Dimension 'B' -Detected $true -SuggestedCheckId 'b'
            New-Probe -Dimension 'C' -Detected $true -SuggestedCheckId 'c'
            New-Probe -Dimension 'D' -Detected $true -SuggestedCheckId 'd'
            New-Probe -Dimension 'E' -Detected $true -SuggestedCheckId 'e'
        )
        $out = @(Invoke-Discovery -Catalog @() -ProbeResults $probes -MaxProposals 3)
        $out.Count | Should -Be 3
    }
}

Describe 'Get-DiscoveryMarkdown' -Tag 'lib' {
    It 'returns placeholder when no proposals' {
        Get-DiscoveryMarkdown -Proposals @() | Should -Match 'No new checks proposed'
    }

    It 'renders each proposal as a bullet with straightforward/needs-approval tag' {
        $proposals = @(
            [pscustomobject]@{
                dimension = 'Docker'; suggested_check_id = 'docker'
                rationale = 'r1'; straightforward = $true
            }
            [pscustomobject]@{
                dimension = 'X'; suggested_check_id = 'x'
                rationale = 'r2'; straightforward = $false
            }
        )
        $md = Get-DiscoveryMarkdown -Proposals $proposals
        $md | Should -Match 'straightforward'
        $md | Should -Match 'needs approval'
        $md | Should -Match '`docker`'
    }
}
