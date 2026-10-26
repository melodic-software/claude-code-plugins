---
bump: minor
---

### Security

- The elevated pass now runs a copy of its files instead of the install tree. The launcher script `New-ElevatedLaunch` writes carries the new `Invoke-ElevatedBootstrap` and a manifest of SHA-256 hashes, taken at prepare time, for the orchestrator, the lib and check scripts, `catalog/checks.jsonc` and `catalog/schemas`. The bootstrap reads each file once and exits 4, copying and running nothing, when one is missing or changed. Otherwise it writes the checked bytes into a new folder under ProgramData that only Administrators and SYSTEM can open, runs the orchestrator from there, and removes the folder.
- Before any module loads, the elevated pass sets `PSModulePath` to machine-wide module folders and gives `Path` and each `HKCU\Environment` variable its system value, or removes it. Prepare refuses a listed file whose name the bootstrap would refuse. `Invoke-CheckWithTimeout` hands each check job the caller's `PSModulePath`, so the pin holds inside checks. A module installed only for the current user, such as PSWindowsUpdate for the drivers check, is no longer seen by the elevated pass.

### Changed

- `elevation-matrix.md`'s residual risk now covers only files changed before prepare, variables `pwsh` reads at startup, and a `pwsh` under the user profile. The audit skill's "Show and ask" step and the elevation banner describe the launcher script to match.
