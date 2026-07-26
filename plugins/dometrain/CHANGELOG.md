# Changelog

All notable changes to the `dometrain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Added

- Setup skill documents the headless bootstrap: `marketplace add`, then `claude plugin install
  --config dometrain_api_key=<your-key>`, then `claude plugin enable`. The enable step is spelled
  out because the plugin ships `defaultEnabled: false` and therefore installs disabled — a
  bootstrap that stops after `install` looks successful and delivers no tools. Also covered: the
  `--config` fresh-install-only caveat and the headless rotation path (uninstall then reinstall
  carrying the SAME `-s <scope>`, read from `claude plugin list`, run from the project directory
  for project/local scope), with a pointer to the README's fuller rotation/exposure-caveat detail
  (`docs/PLUGIN-PHILOSOPHY.md` userConfig conformance).

## [0.1.0]

### Added

- Initial release: remote Dometrain MCP server with native `userConfig` credential storage,
  setup skill, and a grounding skill vendored from Dometrain's official plugin.
