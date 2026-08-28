# Changelog

All notable changes to the `dometrain` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.7]

### Changed

- **Authoring-doctrine pass over `README.md`.** Fixed wording that read two ways or pointed at the wrong place. Every edit was verified against the file by an agent that did not propose it. Prose only; no behavior, contract, or trigger phrase changed.

## [0.2.6]

### Changed

- **The generated options block sits under `## Configuration`.** It was under `## Development`,
  which is contributor documentation a consumer has no reason to open. The generated table itself is
  unchanged; a `## Configuration` heading was added above it. Docs-hygiene sweep,
  L8-write-for-humans.

## [0.2.5]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.2.4]

### Changed

- **Instruction-surface de-slop (#2891, dometrain cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.
  Frontmatter `description` lines and one verbatim Dometrain course title keep their
  em dashes so skill-quality does not treat a rewrite as a dropped trigger, and so the
  citation example stays the published title.

## [0.2.3]

### Changed

- **setup:** normalized restated setup-contract prose (preamble, probe-ladder
  opening, never-writes boundary, and/or headless-reconfigure recipe as present) to the
  canonical fleet wording, keeping the operable text inline with a provenance-only citation
  (whole-repo extract-ssot batch, #2698).
- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.2.2]

### Fixed

- **`setup` skill:** the destructive `claude plugin uninstall` + reinstall recipe for a headless
  key rotation is removed. It rested on an unversioned claim that `claude plugin install
  --config` is ignored once a plugin is installed, and following it dropped this plugin's whole
  stored `pluginConfigs` entry. That claim now appears only as the thing it is — unstamped and
  contradicted for a non-sensitive option at `user` scope on Claude Code 2.1.240, where a plain
  `claude plugin install … --config` against an already-installed plugin printed `already
  installed` and still wrote the value
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)).
  `dometrain_api_key` is `sensitive: true`, which that observation does **not** cover, so
  `/plugin configure dometrain@<marketplace>` remains the prescribed rotation path — it also
  masks input, where a key on the command line lands in shell history and the process table.
- **Docs:** the generated options block no longer presents a post-install `--config` as a
  supported way to rotate this plugin's credential. The 2.1.240 observation behind that claim
  covered a NON-sensitive option, and every option here is `sensitive`, so the block now routes
  rotation to `/plugin configure` — which also masks input — and says plainly that the
  post-install behavior is unverified for a sensitive value
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). Two upstream
  links that pointed at empty backward-compatibility anchors on the settings page were
  repointed at the headings that hold the content.

## [0.2.1]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

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
