# PowerShell Build Commands

PowerShell has no build step — Pester tests and static analysis via PSScriptAnalyzer.

## Test (Pester)

Run when changed files include `*.ps1`, `*.psm1`, `*.Tests.ps1`, or `PSScriptAnalyzerSettings.psd1`, and the project has Pester tests. Prefer the project's documented test runner script when one exists. For a direct invocation, configure the result file to a gitignored artifacts directory:

```powershell
pwsh -NoProfile -Command '
  $config = New-PesterConfiguration
  $config.Run.Path = "<tests-dir>"
  $config.TestResult.Enabled = $true
  $config.TestResult.OutputPath = "artifacts/test-results/pester-results.xml"
  Invoke-Pester -Configuration $config
'
```

**Never use `Invoke-Pester -CI` directly** — its default CWD-relative `testResults.xml` leaks at repo root.

**Install hint:** `Install-PSResource -Name Pester` (or `Install-Module Pester` on older pwsh). On Linux/macOS without pwsh, report `skip`.

## Lint (PSScriptAnalyzer)

```bash
pwsh -NoProfile -Command '
  $files = Get-ChildItem -Path . -Recurse -Include *.ps1,*.psm1 |
    Where-Object { $_.FullName -notlike "*node_modules*" -and $_.FullName -notlike "*.venv*" -and $_.FullName -notlike "*\bin\*" -and $_.FullName -notlike "*\obj\*" }
  if ($files) {
    $files | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName -Settings ./PSScriptAnalyzerSettings.psd1 } | Format-Table -AutoSize
  } else {
    Write-Output "No production .ps1/.psm1 files found"
  }
'
```

Omit `-Settings` when the repo has no `PSScriptAnalyzerSettings.psd1`.

## Gotchas

- **PSScriptAnalyzer has NO `-ExcludePath`** — pre-filter with `-notlike` patterns (NOT `-notmatch` — regex escaping breaks through bash→pwsh)
- **Use `-notlike` with wildcards**, not `-notmatch` with regex — bash→pwsh escaping makes regex unreliable
- **No production `.ps1`/`.psm1` files may exist** — if none found after filtering, report as `skip` with note
- **Settings file** — `PSScriptAnalyzerSettings.psd1` at repo root configures rules when present

## File discovery

PSScriptAnalyzer discovers files via `Get-ChildItem -Recurse`. The filtering above handles exclusions since the tool lacks native path exclusion.
