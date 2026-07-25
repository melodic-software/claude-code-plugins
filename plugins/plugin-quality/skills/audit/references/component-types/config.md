# Auditing plugin config / settings / userConfig

Growable stub. Covers a plugin's configuration surfaces: `userConfig` keys, settings files,
convention/config files the plugin reads.

## Read first

- The plugin's `plugin.json` `userConfig` schema (keys, defaults, `sensitive` flags).
- Any config files the plugin resolves (paths, layer/merge order).
- How defaults are inferred when unset.

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

## Reproduce

Set/unset the key at each scope and confirm the effective value and winner match expectations.
