# Changelog

All notable changes to the `dometrain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.1]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.2.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.1.3]

### Fixed

- Setup skill's headless bootstrap registers the marketplace at the chosen scope:
  `claude plugin marketplace add <source> --scope <scope>`. The bare form writes the registration to
  *user* settings while the `install`/`enable` steps below it carry `-s <scope>`, so a `project`
  bootstrap left a fresh clone or CI agent with the enabled plugin and no marketplace to resolve it
  from (`docs/MIGRATION-PLAYBOOK.md` "Fresh-consumer onboarding"). The prose now also names the flag
  asymmetry: `marketplace add` accepts `--scope` only, while `install` and `enable` also take `-s`.
- Setup skill no longer claims all three rotation commands "default to `user`". `enable`
  auto-detects the scope, which the same file already said forty lines above — the page
  contradicted itself. Corrected to name each command's real default.
- Setup skill's headless rotation drops the no-op `-y` from `claude plugin uninstall` and the false
  rationale attached to it. `-y` skips only `uninstall`'s `--prune` confirmation; the recipe never
  passes `--prune`, so the flag changed nothing and the claimed CI hang could not occur. Completes
  the same correction 0.21.2/0.17.2/0.3.1 landed for `claude-ops`, `session-flow`, and
  `rate-limit-guard`, and 0.2.3 landed for `miro`.

## [0.1.2]

### Fixed

- Setup skill's unreportable-connection bullet now matches the MCP page it cites. Amazon Bedrock,
  Google Cloud's Agent Platform, and Microsoft Foundry form their own group alongside configurations
  without tool search rather than members of it — upstream's "and on" clause makes them additional,
  and tool search is on by default for Claude 4.5-generation models on Agent Platform. Microsoft
  Foundry was missing entirely, and the platform names now match upstream's. The bullet also no
  longer instructs a check the skill cannot run: it may not inspect the environment, so it reports
  the state and routes to `/mcp` rather than naming which configuration is in effect
  (<https://code.claude.com/docs/en/mcp#automatic-reconnection>).

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
