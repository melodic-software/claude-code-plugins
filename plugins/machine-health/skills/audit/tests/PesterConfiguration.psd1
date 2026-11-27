@{
    Run          = @{
        PassThru = $true
        Throw    = $false
    }
    Filter       = @{
        Tag = @()
    }
    Output       = @{
        Verbosity           = 'Detailed'
        StackTraceVerbosity = 'Filtered'
        CIFormat            = 'Auto'
    }
    CodeCoverage = @{
        Enabled               = $false
        OutputFormat          = 'CoverageGutters'
        OutputPath            = 'artifacts/test-results/machine-health-coverage.xml'
        CoveragePercentTarget = 80
    }
    TestResult   = @{
        Enabled      = $true
        OutputFormat = 'NUnitXml'
        OutputPath   = 'artifacts/test-results/machine-health-pester-results.xml'
    }
    Should       = @{
        ErrorAction = 'Stop'
    }
}
