# Auditing plugin config / settings / userConfig

Growable stub. Covers a plugin's configuration surfaces: `userConfig` keys, settings files,
convention/config files the plugin reads.

## Read first

- The plugin's `plugin.json` `userConfig` schema (keys, defaults, `sensitive` flags).
- Any config files the plugin resolves (paths, layer/merge order).
- How defaults are inferred when unset.
- Plugin-shipped harness config at the plugin root: `settings.json`, `.lsp.json`,
  `monitors/monitors.json`.

## Check

- **Resolution correctness** — does config resolution match how Claude Code actually merges scopes
  (user-global + project + local)? Hardcoded paths vs configurable? Directory walk-up or fixed?
  Verify against the current settings reference.
- **SSOT / drift** — does the config duplicate a fact that lives elsewhere (project instructions, a
  hook, a standard tool's config)? Name the single origin; prefer derivation over duplication.
- **Coupling** — is a config file under `.claude/` by necessity or default? Should its path be
  configurable so other tools can consume it (decoupled, tool-agnostic SSOT)?
- **Discoverability & self-description** — a committed single-plugin config file should tell a
  non-plugin reader what it is and that it's safe to ignore without the plugin.
- **Two-surface confusion** — if config is split across file(s) AND userConfig, is that intentional
  and cross-referenced?
- **Secrets** — any credential option must be `sensitive: true` (keychain-backed), never a plain
  settings value.
- **Machine-readable format** — for data other tools must read, prefer flat-scalar YAML (shell-grep
  friendly) over frontmatter-in-markdown or a value trapped in a tool-specific language.
- **Silent no-op keys (`settings.json`)** — a plugin-root `settings.json` supports only the `agent`
  and `subagentStatusLine` keys, silently ignores unknown keys, and takes priority over `settings`
  in `plugin.json`. An unsupported key reads as configuration but does nothing — flag it.
- **Silent-skip LSP entries (`.lsp.json`)** — an entry with an invalid configuration is skipped
  (only `claude --debug` says why); a server that fails to start surfaces in the `/plugin` Errors
  tab. The server binary is a user-machine prerequisite — check it is documented for installers.
- **Monitor noise & portability (`monitors/monitors.json`)** — inspect each monitor's `when`
  trigger before assessing runtime volume: the default `"always"` starts it at session start and on
  plugin reload, while `"on-skill-invoke:<skill-name>"` keeps it dormant until that skill is first
  dispatched. Every stdout line from `command` reaches Claude as a notification; check volume for
  the trigger's actual lifetime and that the command runs on the consumer's platform. (All three
  surfaces per <https://code.claude.com/docs/en/plugins> and
  <https://code.claude.com/docs/en/plugins-reference#monitors>, fetched 2026-08-04.)

## Reproduce

Set/unset the key at each scope and confirm the effective value and winner match expectations.
