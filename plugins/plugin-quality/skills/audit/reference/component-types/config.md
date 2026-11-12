# Auditing plugin config / settings / userConfig

Covers a plugin's configuration: `userConfig` keys, settings files,
convention/config files the plugin reads.

## Read first

- The plugin's `plugin.json` `userConfig` schema (keys, defaults, `sensitive` flags).
- Any config files the plugin resolves (paths, layer/merge order).
- How defaults are inferred when unset.
- Plugin-shipped harness config at the plugin root: `settings.json`, `.lsp.json`,
  `monitors/monitors.json`.

## Check

- **Resolution correctness**: does config resolution match how Claude Code actually merges scopes
  (user-global + project + local)? Hardcoded paths vs configurable? Directory walk-up or fixed?
  Verify against the current settings reference.
- **SSOT / drift**: does the config duplicate a fact that lives elsewhere (project instructions, a
  hook, a standard tool's config)? Name the single origin; prefer derivation over duplication.
- **Coupling**: is a config file under `.claude/` by necessity or default? Should its path be
  configurable so other tools can consume it (decoupled, tool-agnostic SSOT)?
- **Discoverability & self-description**: a committed single-plugin config file should tell a
  non-plugin reader what it is and that it's safe to ignore without the plugin.
- **Two-surface confusion**: if config is split across file(s) AND userConfig, is that intentional
  and cross-referenced?
- **Secrets**: any credential option must be `sensitive: true`, never a plain settings value.
  - **Pointer**: when checking where a `sensitive` value is stored, fetch
    [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
    live.
- **Machine-readable format**: for data other tools must read, prefer flat-scalar YAML (shell-grep
  friendly) over frontmatter-in-markdown or a value trapped in a tool-specific language.
- **Silent no-op keys (`settings.json`)**: flag any key in a plugin-root `settings.json` that the
  Default settings section below does not list as taking effect.
  - **Pointer**: when checking which keys take effect, what happens to the rest, and which of the
    file and the manifest key wins, fetch
    [Default settings](https://code.claude.com/docs/en/plugins/components#default-settings) live.
- **Silent-skip LSP entries (`.lsp.json`)**: check every entry is valid against the
  [`lspServers`](https://code.claude.com/docs/en/plugins/manifest-reference#lspservers) field
  table, and check the server binary is documented for installers as a user-machine prerequisite.
  - **Pointer**: when checking how an invalid entry or a server that fails to start surfaces, fetch
    [LSP servers](https://code.claude.com/docs/en/plugins/components#lsp-servers) live; when
    checking an entry's fields, fetch the `lspServers` section linked above live.
- **Monitor noise & portability (`monitors/monitors.json`)**: inspect each monitor's `when`
  trigger before assessing runtime volume, since the trigger decides when the monitor starts and
  so how long it runs. Every stdout line from `command` reaches Claude as a notification; check
  volume for the trigger's actual lifetime and that the command runs on the consumer's platform.
  - **Pointer**: when reading a monitor's trigger values, its default, and when each starts it,
    fetch [Monitors](https://code.claude.com/docs/en/plugins/manifest-reference#monitors) live;
    when checking what a running monitor's output does, fetch
    [Monitors](https://code.claude.com/docs/en/plugins/components#monitors) live.

## Categories

- **Errors:** a key that does not resolve the way the settings reference says, or a silent no-op key that reads as configuration.
- **Improvements:** a default or scope the schema implies and the resolver does not implement.
- **Quality of life:** an option the operator cannot tell is unset, or a value that only appears inside a file the session does not show.
- **Standards:** the `windows-path-emit` probe for any path the config emits.
- **Emitted findings:** `not-applicable` unless a key gates a component that reports findings; then grade that component's samples under its own lens.

## Reproduce

Set/unset the key at each scope and confirm the effective value and winner match expectations.
