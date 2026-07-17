# Pester v5 configuration for machine-health tests.
# Loaded by Invoke-MachineHealthTests.ps1 via Import-PowerShellDataFile + New-PesterConfiguration.
#
# OutputPath fields are root-relative; the runner absolutizes them against the
# enclosing git working tree (or TEMP outside one) before passing to Pester.
# Pester's native OutputPath is CWD-relative -- absolutizing in the runner
# prevents `testResults.xml`-style leaks when invoked from any CWD.
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
