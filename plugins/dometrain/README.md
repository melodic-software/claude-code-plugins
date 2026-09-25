# dometrain

A Claude Code plugin that connects Claude to [Dometrain](https://dometrain.com)'s hosted course
content over a remote MCP server. Search video-course lessons, pull curated lesson documents
with the exact on-screen code, and cite timestamped deep links so an implementation matches how
the user's courses teach it.

This is the marketplace's first plugin to ship a **remote** (not bundled/local) MCP server: the
server is Dometrain-hosted (`https://mcp.dometrain.com/mcp`), closed-source, and requires an
active [Dometrain Pro](https://dometrain.com/dometrain-pro/) subscription. There is nothing to bundle,
unlike `miro`'s locally-run, self-contained Node server.

## Enabling and configuration

The plugin **installs disabled** (`defaultEnabled: false`). A remote MCP server that connects
to an external, credentialed service is opt-in, not on by default. Enable it with
`claude plugin enable dometrain` or the `/plugin` interface, and provide a key, either at the
prompt or from an environment variable (see
[Reading the key from an environment variable](#reading-the-key-from-an-environment-variable)):

| Option | Storage | Purpose |
|---|---|---|
| `dometrain_api_key` | Claude Code secure credential storage (never `settings.json`) | Dometrain account API key. Optional, so you can leave it blank when an override supplies the key. The server rejects requests that carry no key. |

Get a key from <https://dometrain.com/dashboard/account/> ("MCP API keys" section). Claude Code
prompts for it at enable time (masked input). Sensitive values use the macOS Keychain, or
`~/.claude/.credentials.json` on platforms where no supported keychain is available; the key is
substituted into the server's `.mcp.json` `Authorization` header as a Bearer token.

Headless install with the key seeded on first install:

```shell
claude plugin install dometrain@<marketplace> --config dometrain_api_key=<your-key>
```

**Security note:** passing the key as a CLI argument records it in shell history
(`.bash_history`, `.zsh_history`) and briefly exposes it in the process table
(`/proc/<pid>/cmdline`, `ps aux`) while the command runs. The interactive `/plugin`
prompt masks input and never touches either surface. In CI/CD, route the value through
your secrets manager rather than inlining it literally; interactively, clear your shell history
afterward or prefix the command with a leading space if your shell supports that convention.

Run `/dometrain:setup` to check enablement and MCP tool availability. The setup skill never
reads or exposes the key and never calls a Dometrain tool during setup. See
[Setup mechanism](#setup-mechanism) below for why.

### Rotating or clearing the key

Once set, a sensitive `userConfig` value has no dedicated menu entry in the `/plugin` detail
view, and the `/mcp` server menu's "Clear authentication" only applies to OAuth-based servers.
It is a no-op for this plugin's static Bearer-header auth (verified: reconnecting after "Clear
authentication" here silently reuses the existing stored key). To change or clear
`dometrain_api_key` later, run:

```text
/plugin configure dometrain@<marketplace>
```

This reopens the same configuration screen shown at first enable, letting you overwrite or blank
the key at any time. It is the recommended rotation path regardless. It masks input, where a key
passed on the command line lands in shell history and the process table, exactly as the security
note above describes.

The older claim that `--config` is ignored once the plugin is installed was never
version-stamped. Headless `--config` against an already-installed plugin writes a
non-sensitive option; whether that holds for a `sensitive` option such as
`dometrain_api_key` has not been verified, so do not rely on it for a credential, and
do not uninstall to rotate: that drops this plugin's entire stored `pluginConfigs`
entry, resetting every option in the Options reference table below to its manifest
default. The verified-version record lives in the
[plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

## Reading the key from an environment variable

To take the key from `DOMETRAIN_API_KEY`, the variable Dometrain's own plugin reads, leave
`dometrain_api_key` blank at the enable prompt and add a **user-scope** HTTP server at the
plugin's exact URL:

```shell
claude mcp add-json dometrain \
  '{"type":"http","url":"https://mcp.dometrain.com/mcp","headers":{"Authorization":"Bearer ${DOMETRAIN_API_KEY}"}}' \
  --scope user
```

The single quotes keep your shell from expanding the variable, so the stored config holds the
reference, not the key. Claude Code expands `${DOMETRAIN_API_KEY}` from its own environment each
time it connects. Plugin servers are deduplicated by endpoint and user scope outranks them, so
this entry replaces the plugin's server.

This is a choice you make once, not a per-session fallback. While the entry exists it always wins,
and if `DOMETRAIN_API_KEY` is unset Claude Code sends the literal `${DOMETRAIN_API_KEY}` text and
flags a missing-variable warning in `claude mcp list`. Remove the entry
(`claude mcp remove dometrain --scope user`) to fall back to the stored `dometrain_api_key`.

The plugin's own `.mcp.json` keeps `${user_config.dometrain_api_key}` rather than a combined
`${DOMETRAIN_API_KEY:-${user_config.dometrain_api_key}}`. The MCP docs define the `:-` fallback
with a literal default and do not document a `${user_config.*}` reference inside it, so this
plugin does not rely on one.

The notes under [Using vault-exec](#using-vault-exec-opt-in) on tool-name prefixes and Grok apply
here too.

Basis: [MCP server configuration](https://code.claude.com/docs/en/mcp), "Environment variable
expansion in `.mcp.json`" and "Scope hierarchy and precedence," verified 2026-09-25.

## Using vault-exec (opt-in)

If your machine resolves vendor API keys from a secret store at launch time instead of typing
them into app UIs (see
[melodic-software/dotfiles ADR 0005](https://github.com/melodic-software/dotfiles/blob/main/docs/adr/0005-adopt-vault-exec-as-the-secret-resolver.md)),
you can keep `dometrain_api_key` out of Claude Code's secure credential storage and let
`vault-exec` mint the `Authorization` header at connect time instead. This is entirely opt-in.
Skip it and the plugin behaves exactly as described above.

1. Enable the plugin and leave `dometrain_api_key` blank. It is optional, and the recipe below
   replaces the plugin's server with one at the identical URL.
2. Add a **user-scope** HTTP MCP server at the *same URL* this plugin uses
   (`https://mcp.dometrain.com/mcp`) with a `headersHelper` that resolves the key through
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

3. Claude Code deduplicates a plugin-provided server against one configured at local, project, or
   user scope by **endpoint**. Because your user-scope server names the identical URL, it outranks
   and replaces the plugin's own server; no `/mcp` disable step is needed here, unlike `miro`'s
   wrapped-command recipe, where the launch command itself differs.

Notes:

- Claude Code gives the helper a 10-second budget with no caching; it reruns on every reconnect
  and once more on a `401`/`403`. Time your own `vault-exec` call once. A cold vault lookup can
  come close to that budget.
- Whatever the helper prints to stdout is the bearer token. Never add logging or `-x` tracing to
  the script above.
- The folder-trust gate that can hold a `headersHelper` back until you accept a trust dialog
  applies to a server declared in a project `.mcp.json` or at local scope. A user-scope server,
  like the one above, is not gated by it.
- Tool names move from `mcp__plugin_dometrain_dometrain__<tool>` (plugin-provided) to
  `mcp__dometrain__<tool>` (directly configured) once the override is active. Update any
  permission rule written against the old prefix.
- Grok CLI also loads Claude Code plugin servers, without Claude Code's substitution of
  `${user_config.*}`, and ranks its own config above them. Give it a `dometrain` entry of its own
  in `~/.grok/config.toml`, as
  [ADR 0005](https://github.com/melodic-software/dotfiles/blob/main/docs/adr/0005-adopt-vault-exec-as-the-secret-resolver.md)
  records.

Basis: [MCP server configuration](https://code.claude.com/docs/en/mcp), "Headers helper," "Plugin
MCP tool names," and "Server deduplication," verified 2026-09-23.

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

## Why a remote server, not bundled

Unlike `miro`'s bundled local `stdio` server, Dometrain's server is hosted and closed-source.
There is no artifact to bundle. The plugin wires Claude Code's `http`-type MCP transport
directly at `https://mcp.dometrain.com/mcp` with a Bearer header sourced from `userConfig` (or
from a user-scope override at the same URL), never a locally-run process.

## Dometrain's own official plugin, and why this one exists too

Dometrain ships its own official Claude Code plugin and marketplace at
[github.com/Dometrain/mcp](https://github.com/Dometrain/mcp) (MIT licensed), installable via:

```shell
claude plugin marketplace add dometrain/mcp
claude plugin install dometrain@dometrain
```

That plugin's `.mcp.json` authenticates via a shell environment variable
(`${DOMETRAIN_API_KEY}`). It declares no `userConfig` field at all. This plugin exists
specifically to provide the alternative: the key entered once through Claude Code's **native
masked `userConfig` prompt**, stored in secure credential storage, with no shell environment
variable to export. The environment variable route stays available as an override (see
[Reading the key from an environment variable](#reading-the-key-from-an-environment-variable)).

**Do not enable both plugins simultaneously.** Both share the identical plugin name
(`"dometrain"`) in their respective `plugin.json` manifests. Install identity is
marketplace-scoped (`dometrain@<marketplace>` and `dometrain@dometrain` are distinct,
coexistable install identities), but skill and MCP-tool namespacing is driven by `plugin.json`
`name` alone, and Claude Code's behavior for two enabled plugins sharing an
identical name is genuinely undocumented. Pick one.

## Grounding skill

`/dometrain:grounding` carries usage guidance adapted from Dometrain's own official
`dometrain-grounding` skill: when to consult Dometrain, the tool workflow, citation format, and
quota etiquette (same source repo as above, MIT licensed). Model-invocable: Claude
proactively consults it on a covered topic without an explicit command.

## Keeping the grounding skill in sync

The grounding skill's usage guidance is vendored, not hand-copied, from Dometrain's own skill
content. `/dometrain:sync` is **maintainer-only, never model-invocable, and report-only for
consumers**. It checks whether upstream has changed. See
[`skills/sync/context/update.md`](skills/sync/context/update.md) for the full integration
protocol; only a maintainer working in a clone of this repository refreshes the baseline.

## Setup mechanism

`/dometrain:setup check` reports one of `disabled`, `connected`, or `failed or unverified`,
derived from tool-inventory presence and Claude Code's own `ToolSearch`-surfaced connection
errors, not from reading `/mcp` connection status, which no callable tool exposes to a model
turn. See [`skills/setup/SKILL.md`](skills/setup/SKILL.md) for the full mechanism.

## Attribution

This plugin's `grounding` skill content is adapted from Dometrain's own official Claude Code
plugin ([github.com/Dometrain/mcp](https://github.com/Dometrain/mcp)), MIT licensed. The
Dometrain course content served by the MCP server itself is **not** covered by that license. It
remains Dometrain's proprietary content, accessible under your Dometrain Pro subscription and
[Dometrain's terms of service](https://dometrain.com/terms/).

## Development

This plugin ships no server code. The MCP server is Dometrain-hosted. There is no build step;
`claude plugin validate plugins/dometrain` is the only local check.

## Configuration

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `dometrain_api_key` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_DOMETRAIN_API_KEY` | **Sensitive**: stored in the OS keychain or protected credentials file. Dometrain account API key from https://dometrain.com/dashboard/account/ (MCP API keys section). Optional: leave it blank when a user-scope MCP server at the same URL supplies the key from DOMETRAIN_API_KEY or a secret store (see the README). The remote server rejects requests that carry no key. Stored by Claude Code in secure credential storage, never settings.json. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure dometrain@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install dometrain@<marketplace> -s <scope> --config dometrain_api_key=<value>
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
       "dometrain@<marketplace>": {
         "options": {
           "dometrain_api_key": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
