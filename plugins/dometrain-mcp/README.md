# dometrain-mcp

The bundled [Dometrain](https://dometrain.com) MCP server for the
[`dometrain`](../dometrain) grounding skills. It connects Claude Code to Dometrain's hosted course
content: search video-course lessons, pull curated lesson documents with the exact on-screen code,
and cite timestamped deep links.

The server is Dometrain-hosted (`https://mcp.dometrain.com/mcp`), closed-source, and requires an
active [Dometrain Pro](https://dometrain.com/dometrain-pro/) subscription. This plugin ships no
server code, only the `http` connection and a masked prompt for the key.

## Which plugins to install

| Your setup | Install | Result |
|---|---|---|
| No Dometrain MCP server yet | `dometrain` and `dometrain-mcp` | Zero setup beyond entering the key |
| Your own user-scope `dometrain` server | `dometrain` only | Grounding skills use your server; no duplicate-server warning |

Claude Code matches plugin servers to already-configured servers by endpoint, not by name. With
your own server at `https://mcp.dometrain.com/mcp` and this plugin enabled too, `/plugin` shows a
warning that the plugin's server was skipped as a duplicate. Your server keeps working. Skip this
plugin to avoid the warning.

## Enabling and configuration

The plugin **installs disabled** (`defaultEnabled: false`). A remote MCP server that connects to
an external, credentialed service is opt-in. Enable it with `claude plugin enable dometrain-mcp`
or the `/plugin` interface:

| Option | Storage | Purpose |
|---|---|---|
| `dometrain_api_key` | Claude Code secure credential storage (never `settings.json`) | Dometrain account API key. Optional, so the plugin enables with it blank. The server rejects requests that carry no key. |

Get a key from <https://dometrain.com/dashboard/account/> ("MCP API keys" section). Claude Code
prompts for it at enable time (masked input). Sensitive values use the macOS Keychain, or
`~/.claude/.credentials.json` on platforms where no supported keychain is available; the key is
substituted into the server's `.mcp.json` `Authorization` header as a Bearer token.

Headless install with the key seeded on first install:

```shell
claude plugin install dometrain-mcp@<marketplace> --config dometrain_api_key=<your-key>
```

**Security note:** passing the key as a CLI argument records it in shell history
(`.bash_history`, `.zsh_history`) and briefly exposes it in the process table
(`/proc/<pid>/cmdline`, `ps aux`) while the command runs. The interactive `/plugin`
prompt masks input and never touches either surface. In CI/CD, route the value through
your secrets manager rather than inlining it literally; interactively, clear your shell history
afterward or prefix the command with a leading space if your shell supports that convention.

Run `/dometrain:setup` to check that the tools are available. It never reads or exposes the key
and never calls a Dometrain tool.

### Rotating or clearing the key

Once set, a sensitive `userConfig` value has no dedicated menu entry in the `/plugin` detail
view, and the `/mcp` server menu's "Clear authentication" only applies to OAuth-based servers.
It is a no-op for this plugin's static Bearer-header auth (verified: reconnecting after "Clear
authentication" here silently reuses the existing stored key). To change or clear
`dometrain_api_key` later, run:

```text
/plugin configure dometrain-mcp@<marketplace>
```

This reopens the same configuration screen shown at first enable, letting you overwrite or blank
the key at any time. It is the recommended rotation path: it masks input, where a key passed on
the command line lands in shell history and the process table.

Headless `--config` against an already-installed plugin writes a non-sensitive option; whether
that holds for a `sensitive` option such as `dometrain_api_key` has not been verified, so do not
rely on it for a credential. Do not uninstall to rotate: that drops this plugin's entire stored
`pluginConfigs` entry, resetting every option in the Options reference table below to its
manifest default. The verified-version record lives in the
[plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

## Tool names

Plugin-provided tools are named `mcp__plugin_<plugin>_<server>__<tool>`, so this plugin's tools
appear as `mcp__plugin_dometrain-mcp_dometrain__<tool>`. A server you configure yourself appears
as `mcp__dometrain__<tool>`. Write permission rules against the prefix of the setup you use. The skills do not depend on the
prefix; they match the `dometrain` server segment and tool name.

Basis: [MCP server configuration](https://code.claude.com/docs/en/mcp), "Plugin MCP tool names",
and a live tool inventory showing a hyphenated plugin name kept as-is, as of 2026-09-29. Recheck
when Claude Code changes how it names MCP tools.

## Tools

| Tool | What it does |
|---|---|
| `search_dometrain(query, tech?, max_results?)` | Search lessons for implementation guidance; hybrid keyword + semantic ranking. Ranked excerpts with deep links |
| `search_code(query, language?, max_results?)` | Search the code shown on screen in lessons; snippets with a deep link to the exact moment the code appears |
| `get_lesson(lesson_id)` | Full curated lesson document: summary, key concepts, notes, on-screen code |
| `get_course(course_id_or_slug)` | Course overview + chapter/lesson tree |
| `list_courses(topic?)` | Published courses, optionally filtered by topic |
| `get_usage()` | Your monthly request usage, limit, and reset date |

All six tools are read-only. Nothing to execute, nothing this plugin mutates.

## Quota

Requests are limited per calendar month per account (all your keys share the pool), with a
short per-minute burst cap. Figures change on Dometrain's side independently of this plugin, so
this README does not hardcode them. Call `get_usage()`, or check your own
[Dometrain dashboard](https://dometrain.com/dashboard/account/), for current numbers.

## Using your own server instead

Install only [`dometrain`](../dometrain) and skip this plugin when you want the key to come from an
environment variable or a secret store. With no plugin server at the same endpoint, no
duplicate-server warning appears, and the grounding skills use your server. Both recipes register a
**user-scope** HTTP server named `dometrain` at `https://mcp.dometrain.com/mcp`.

### Reading the key from an environment variable

To take the key from `DOMETRAIN_API_KEY`, the variable Dometrain's own plugin reads:

```shell
claude mcp add-json dometrain \
  '{"type":"http","url":"https://mcp.dometrain.com/mcp","headers":{"Authorization":"Bearer ${DOMETRAIN_API_KEY}"}}' \
  --scope user
```

The single quotes keep your shell from expanding the variable, so the stored config holds the
reference, not the key. Claude Code expands `${DOMETRAIN_API_KEY}` from its own environment each
time it connects. If `DOMETRAIN_API_KEY` is unset, Claude Code sends the literal
`${DOMETRAIN_API_KEY}` text and flags a missing-variable warning in `claude mcp list`.

Basis: [MCP server configuration](https://code.claude.com/docs/en/mcp), "Environment variable
expansion in `.mcp.json`" and "Scope hierarchy and precedence."

### Using vault-exec (opt-in)

If your machine resolves vendor API keys from a secret store at launch time instead of typing
them into app UIs (see
[melodic-software/dotfiles ADR 0005](https://github.com/melodic-software/dotfiles/blob/main/docs/adr/0005-adopt-vault-exec-as-the-secret-resolver.md)),
let `vault-exec` mint the `Authorization` header at connect time:

1. Add a user-scope HTTP MCP server with a `headersHelper` that resolves the key through
   `vault-exec` and prints the `Authorization` header as JSON:

   ```shell
   claude mcp add-json dometrain \
     '{"type":"http","url":"https://mcp.dometrain.com/mcp","headersHelper":"/path/to/dometrain-headers.sh"}' \
     --scope user
   ```

   where `/path/to/dometrain-headers.sh` is an executable script you keep in your own dotfiles:

   ```bash
   #!/usr/bin/env bash
   vault-exec --env DOMETRAIN_API_KEY=<your-secret-name> -- \
     sh -c 'printf "{\"Authorization\":\"Bearer %s\"}" "$DOMETRAIN_API_KEY"'
   ```

   Replace `<your-secret-name>` with whatever name your vault stores the key under; this plugin
   never sees or manages that name. `vault-exec` places the resolved key only in the child
   environment, never on an argument list, and this script reads it back through a shell variable
   expansion so the key never appears on a command line. The `vault-exec.ps1` PowerShell wrapper
   resolves the same way on Windows, but the shell a plugin-independent `headersHelper` runs on
   Windows is unverified. Confirm it before relying on it.

2. Install `dometrain` and not `dometrain-mcp`.

Notes:

- Claude Code gives the helper a 10-second budget with no caching; it reruns on every reconnect
  and once more on a `401`/`403`. Time your own `vault-exec` call once. A cold vault lookup can
  come close to that budget.
- Whatever the helper prints to stdout is the bearer token. Never add logging or `-x` tracing to
  the script above.
- The folder-trust gate that can hold a `headersHelper` back until you accept a trust dialog
  applies to a server declared in a project `.mcp.json` or at local scope. A user-scope server,
  like the one above, is not gated by it.
- Grok CLI also loads Claude Code plugin servers, without Claude Code's substitution of
  `${user_config.*}`, and ranks its own config above them. Give it a `dometrain` entry of its own
  in `~/.grok/config.toml`, as
  [ADR 0005](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/adr/0005-adopt-vault-exec-as-the-secret-resolver.md)
  records.

Basis: [MCP server configuration](https://code.claude.com/docs/en/mcp), "Headers helper," "Plugin
MCP tool names," and "Server deduplication."

## Dometrain's own official plugin

Dometrain ships its own official Claude Code plugin and marketplace at
[github.com/Dometrain/mcp](https://github.com/Dometrain/mcp) (MIT licensed). Its `.mcp.json`
authenticates through the `DOMETRAIN_API_KEY` shell variable and declares no `userConfig`. This
plugin is the alternative: the key entered once through Claude Code's native masked `userConfig`
prompt, with no shell variable to export. Its plugin is named `dometrain`, the same name as this
marketplace's grounding plugin, so do not enable both.

## Development

This plugin ships no server code. There is no build step;
`claude plugin validate plugins/dometrain-mcp` is the only local check.

## Configuration

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `dometrain_api_key` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_DOMETRAIN_API_KEY` | **Sensitive**: stored in the OS keychain or protected credentials file. Dometrain account API key from https://dometrain.com/dashboard/account/ (MCP API keys section). Optional at enable time, but the remote server rejects requests that carry no key. Stored by Claude Code in secure credential storage, never settings.json. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure dometrain-mcp@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install dometrain-mcp@<marketplace> -s <scope> --config dometrain_api_key=<value>
   ```

   Route 1 is the rotation path for this plugin, not this one. Every option here is
   `sensitive`, and `/plugin configure` masks input. A secret passed on the command
   line lands in shell history and the process table. Do not rely on this command to
   rotate a credential; the verified-version record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).
   Do **not**
   `claude plugin uninstall` to reconfigure either: uninstalling drops this
   plugin's whole stored `pluginConfigs` entry, resetting every option in the table
   above to its default.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "dometrain-mcp@<marketplace>": {
         "options": {
           "dometrain_api_key": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user** and managed settings only, **not**
   from a project's `.claude/settings.json`. To vary behavior per repository,
   enable or disable the plugin in that project's `enabledPlugins` instead of
   setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
