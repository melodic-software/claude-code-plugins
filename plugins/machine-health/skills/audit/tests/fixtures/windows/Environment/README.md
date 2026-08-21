# Environment registry fixtures

Synthetic snapshots of `HKCU:\Environment` and
`HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment`.
These are not captured CLIXML: a live `RegistryKey` does not round-trip
through `Export-Clixml` in a form Pester can rehydrate on a non-Windows
host, and the interesting cases (2047-character Path, a planted secret)
must not come from a real workstation.

Each `*.json` is a `{ "user": { Name: { kind, value } }, "machine": {...},
"dirs": { token: { exists, files } } }` document. Tests replace `{token}`
placeholders with materialized temp directories before mocking `Get-Item`.

Credential fixtures use a planted value that tests assert is **absent**
from JSON and `-Human` output.

| File | Scenario |
|---|---|
| `healthy.json` | ExpandString User Path, existing dirs, no flags |
| `disable-autoupdater.json` | User `DISABLE_AUTOUPDATER=1` |
| `duplicate-and-missing-path.json` | Duplicate User Path entry + one missing dir |
| `shadowed-exe.json` | Same `git.exe` in User and Machine Path dirs |
| `shadow-machine-wins.json` | Process PATH lists Machine dir first |
| `path-reg-sz.json` | User Path stored as `REG_SZ` (`String`) |
| `path-length-warn.json` | User Path length ≥ 1800 and < 2047 |
| `path-length-crit.json` | User Path length ≥ 2047 |
| `credential-names.json` | `GITHUB_TOKEN` planted; value must never be emitted |
