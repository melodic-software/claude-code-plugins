# Changelog

All notable changes to the `miro` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.2]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@melodic-software`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.3.1]

### Changed

- **Bump `@hono/node-server` from 1.19.14 to 2.1.0** (#2508).

## [0.3.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.3]

### Fixed

- Setup skill's headless bootstrap registers the marketplace at the chosen scope:
  `claude plugin marketplace add <source> --scope <scope>`. The bare form writes the registration to
  *user* settings while the `install`/`enable` steps below it carry `-s <scope>`, so a `project`
  bootstrap left a fresh clone or CI agent with the enabled plugin and no marketplace to resolve it
  from (`docs/MIGRATION-PLAYBOOK.md` "Fresh-consumer onboarding"). The prose now also names the flag
  asymmetry: `marketplace add` accepts `--scope` only, while `install` and `enable` also take `-s`.
- Setup skill's headless rotation drops the no-op `-y` from `claude plugin uninstall` and the false
  rationale attached to it. `-y` skips only `uninstall`'s `--prune` confirmation; the recipe never
  passes `--prune`, so the flag changed nothing and the claimed CI hang could not occur. Completes
  the same correction 0.21.2/0.17.2/0.3.1 landed for `claude-ops`, `session-flow`, and
  `rate-limit-guard`.

## [0.2.2]

### Added

- Setup skill documents the headless bootstrap: `marketplace add`, then
  `claude plugin install --config miro_api_token=<token>`, then `claude plugin enable`. The enable
  step is spelled out because the plugin ships `defaultEnabled: false` and therefore installs
  disabled — a bootstrap that stops after `install` looks successful and delivers no tools. Also
  covered: the `--config` fresh-install-only caveat, the headless rotation path (uninstall then
  reinstall carrying the SAME `-s <scope>`, read from `claude plugin list`, run from the project
  directory for project/local scope), and the shell-history/process-table exposure caveat
  (`docs/PLUGIN-PHILOSOPHY.md` userConfig conformance).

### Changed

- MCP server version kept aligned with the plugin: `package.json`, the
  server's MCP `Implementation` version, the lockfile, and the committed
  bundle all report `0.2.2`.

## [0.2.1]

### Added

- **README section "Rotating or clearing the token"** naming
  `/plugin configure miro` as the rotation/clear path for the stored
  `miro_api_token`, per the repo's sensitive-`userConfig` README convention.

### Changed

- MCP server version kept aligned with the plugin: `package.json`, the
  server's MCP `Implementation` version, the lockfile, and the committed
  bundle all report `0.2.1`.

## [0.2.0]

### Changed

- **Setup adopts the uniform contract's check-only carve-out** (fleet
  conformance wave, dim 8). The plugin's entire configuration is the native
  sensitive `miro_api_token` userConfig, so `check` is the sole action; the
  optional read-only credential probe is now the explicit `check verify-api`
  argument instead of an in-flow question — setup stays non-interactive and
  never touches the token or `pluginConfigs`.
- MCP server version kept aligned with the plugin: `package.json`, the
  server's MCP `Implementation` version, the lockfile, and the committed
  bundle all report `0.2.0`.

## [0.1.2]

### Added

- This changelog (fleet conformance wave: every versioned plugin ships a
  Keep-a-Changelog file).

### Changed

- MCP server version aligned with the plugin: `package.json`, the server's
  MCP `Implementation` version, and the committed bundle now all report
  `0.1.2` (they had drifted to `0.1.0` while `plugin.json` was `0.1.1`).

## [0.1.1]

First versioned release covered by this changelog; see the git history of
`plugins/miro/` for earlier changes.
