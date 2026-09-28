#Requires -Version 7.4
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.7.0' }

BeforeAll {
    . "$PSScriptRoot\..\..\helpers\Initialize-CheckSuite.ps1" -LibScript 'ConvertTo-DetailMarkdown.ps1'
}

Describe 'ConvertTo-DetailMarkdown' -Tag 'lib' {
    It 'returns $null for a missing or empty detail' {
        ConvertTo-DetailMarkdown -Detail $null | Should -BeNullOrEmpty
        ConvertTo-DetailMarkdown -Detail ([pscustomobject]@{}) | Should -BeNullOrEmpty
    }

    It 'renders scalars as a key/value table, hashtable or round-tripped object alike' {
        $detail = [ordered]@{ kev_match_count = 3; kev_upgrade_count = 1; module_used = 'winget' }
        foreach ($shape in @($detail, ([pscustomobject]$detail | ConvertTo-Json | ConvertFrom-Json))) {
            $md = ConvertTo-DetailMarkdown -Detail $shape
            $md | Should -Match '(?m)^\| Detail \| Value \|$'
            $md | Should -Match '(?m)^\| `kev_match_count` \| 3 \|$'
            $md | Should -Match '(?m)^\| `module_used` \| winget \|$'
        }
    }

    It 'renders collections as a count, previewing scalar lists only' {
        $detail = [pscustomobject]@{
            unexpected_paths = @('C:\a', 'C:\b', 'C:\c', 'C:\d')
            kev_matches      = @([pscustomobject]@{ cve_id = 'CVE-1' }, [pscustomobject]@{ cve_id = 'CVE-2' })
            empty_list       = @()
        }
        $md = ConvertTo-DetailMarkdown -Detail $detail
        $md | Should -Match '\| `unexpected_paths` \| 4 items: C:\\a, C:\\b, C:\\c, \.\.\. \|'
        $md | Should -Match '\| `kev_matches` \| 2 items \|'
        $md | Should -Not -Match 'empty_list'
    }

    It 'lists scalars before collections so counts survive truncation' {
        $detail = [ordered]@{ events = @(1, 2); total_events = 2 }
        $md = ConvertTo-DetailMarkdown -Detail $detail
        $md.IndexOf('total_events') | Should -BeLessThan $md.IndexOf('`events`')
    }

    It 'truncates past MaxRows and names how many fields remain' {
        $detail = [ordered]@{}
        1..14 | ForEach-Object { $detail["k$_"] = $_ }
        $md = ConvertTo-DetailMarkdown -Detail $detail -MaxRows 10
        @($md -split "`n" | Where-Object { $_ -match '^\| `k' }).Count | Should -Be 10
        $md | Should -Match '_4 more detail field\(s\) in latest\.json\._'
    }

    It 'escapes pipes, collapses line breaks, and cuts long values' {
        $detail = [pscustomobject]@{ message = "a|b`r`nsecond line"; long = ('x' * 200) }
        $md = ConvertTo-DetailMarkdown -Detail $detail
        $md | Should -Match '\| `message` \| a\\\|b second line \|'
        $md | Should -Match '\| `long` \| x{117}\.\.\. \|'
    }
}
