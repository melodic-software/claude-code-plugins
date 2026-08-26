# Changelog

All notable changes to the `miro` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.8]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.3.7]

### Changed

- **Instruction-surface de-slop (#2891, miro cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change.
  The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.3.6]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).

## [0.3.5]

### Fixed

- **`setup` skill:** the destructive `claude plugin uninstall` + reinstall recipe for a headless
  token rotation is removed. It rested on an unversioned claim that `claude plugin install
  --config` is ignored once a plugin is installed, and following it dropped this plugin's whole
  stored `pluginConfigs` entry. That claim now appears only as the thing it is — unstamped and
  contradicted for a non-sensitive option at `user` scope on Claude Code 2.1.240, where a plain
  `claude plugin install … --config` against an already-installed plugin printed `already
  installed` and still wrote the value
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)).
  `miro_api_token` is `sensitive: true`, which that observation does **not** cover, so `/plugin
  configure miro@<marketplace>` remains the prescribed rotation path — it also masks input,
  where a token on the command line lands in shell history and the process table.
- **Docs:** the generated options block no longer presents a post-install `--config` as a
  supported way to rotate this plugin's credential. The 2.1.240 observation behind that claim
  covered a NON-sensitive option, and every option here is `sensitive`, so the block now routes
  rotation to `/plugin configure` — which also masks input — and says plainly that the
  post-install behavior is unverified for a sensitive value
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). Two upstream
  links that pointed at empty backward-compatibility anchors on the settings page were
  repointed at the headings that hold the content.

## [0.3.4]

### Changed

- **Bump the npm-minor-patch group** (#3020): `@biomejs/biome` 2.5.7→2.5.8, `@types/node` 26.1.2→26.2.0, `esbuild` 0.28.1→0.28.2.

## [0.3.3]

### Changed

- Behavior-preserving simplifications from the repository-wide batch-simplify pass:
  duplicated helpers folded, dead code and redundant constructs removed, no functional
  change. Every group was verified by a fresh-context verifier agent against the
  plugin's own test suite.

## [0.3.2]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
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
