---
bump: minor
---

### Added

- `block-cross-domain` denies a call that switches gh's account or removes `GH_TOKEN` from a session whose domain has a `gh_config_dir`, whatever `GH_CONFIG_DIR` the call runs with. Denied: `gh auth switch`, `gh auth login` and `gh auth logout`; `unset GH_TOKEN`, `export -n GH_TOKEN` and `env -u GH_TOKEN` in each spelling; an assignment that empties `GH_TOKEN` (`GH_TOKEN=`, PowerShell's `$env:GH_TOKEN = ''` or `= $null`); and PowerShell's `Remove-Item Env:GH_TOKEN`. A plain `gh` call, `gh auth status` and `gh auth token` included, is still judged by the config-directory rule alone. Sessions in a domain with no `gh_config_dir`, and neutral sessions, are not affected. The deny's telemetry `form` is `auth-deny`.
