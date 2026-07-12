# Captured + redacted Pester fixtures

Each subdirectory corresponds to one cmdlet. Fixtures captured via `tests/helpers/New-Fixture.ps1`, redacted via `tests/helpers/Invoke-FixtureRedaction.ps1`.

## Layout

```text
fixtures/windows/
  <Cmdlet-Name>/
    <scenario>.clixml           # Captured from real host
    <scenario>.synthetic.clixml # Hand-authored (edge cases the host can't produce)
    README.md                   # Describes each scenario in this directory
```

## Adding a fixture

```powershell
# Capture from current host
pwsh -File tests/helpers/New-Fixture.ps1 -Cmdlet Get-Volume -Scenario all-volumes

# Capture with drive-letter preservation
pwsh -File tests/helpers/New-Fixture.ps1 -Cmdlet Get-Volume -Scenario low-free-space -PreserveDriveLetter C
```

Review output before committing — redaction is best-effort and catches common machine-specific values, but vendor-specific strings may leak.

## Refreshing a fixture

```powershell
pwsh -File tests/helpers/New-Fixture.ps1 -Cmdlet Get-Volume -Scenario all-volumes -OverwriteExisting
```

Only refresh when a test fails due to cmdlet output-shape change on a new Windows version.

## Budget

- Per fixture: ≤ 50 KB
- Per cmdlet directory: ≤ 500 KB

Exceeding budget signals to reduce captured data (add -First N when capturing, or use a synthetic fixture).
