# gaming

A Claude Code plugin that applies the community DLSS 5 Neural Rendering mod to PC games, tracks
what it changed, and removes it again byte for byte. The mod is an OptiScaler fork that loads
NVIDIA's DLSS 5 runtime (`nvngx_dlssnr.dll`) into games that do not ship it natively.

Invoke it with `/gaming:dlss5` and an action: `assess`, `apply`, `remove`, `status`, `tune`, or
`refetch`. Run `/gaming:setup` first.

## Windows only

The mod, the NVIDIA runtime, and the games are Windows binaries, and the plugin's script is
PowerShell 7 (`pwsh`). It needs an NVIDIA RTX 50-series GPU with a driver that supports DLSS 5.
There is no macOS or Linux path, and the plugin does not pretend otherwise.

## What the plugin ships, and what it does not

The plugin ships no NVIDIA binary and names no source for one. The runtime DLL reaches your data
directory from one of three places, all yours:

1. a path you configure (`runtime_dll`);
2. a DLSS 5 title installed on your own machine, which `setup apply` scans for and copies from;
3. a `runtime_source` you configure: a local or network path, or a plain `https://` URL.

Every copy is checked against the known-good SHA-256 or a valid NVIDIA Authenticode signature
before use. The license terms of whatever source you configure are your responsibility. The fork
builds are downloaded from their public GitHub releases by pinned URL and pinned SHA-256.

## Safety

- The mod is never applied to a game with anti-cheat on disk, and `assess` asks for the Steam
  store page's anti-cheat section before a first apply. Injecting a DLL into an online game with
  anti-cheat risks an account ban.
- `apply` never overwrites an existing game file. It refuses before copying on any collision.
- `remove` deletes only files its manifest or the known byproduct list names, so a removed mod
  leaves the game folder as it was.
- The forks' `setup_windows.bat` is interactive and never run; the plugin renames the proxy DLL
  itself.

## Configuration

Three plugin options: `data_dir` (directory) holds the ledger, snapshots, manifests, fork builds
and the runtime DLL, and defaults to `Documents\Gaming` under your user profile; `runtime_dll`
(file) points at a runtime DLL you already have; `runtime_source` (string) points at a copy you
host. All are optional.

`data_dir` survives `claude plugin uninstall`. Changing `data_dir` after applying the mod to a
game is a move of the directory, not a reconfiguration: move the old directory's contents to the
new path, or `status` and `remove` lose track of the modded games.

`runtime_source` is stored in plain text in `settings.json`, so it must not carry a credential.
A URL with a query string is refused, because signed-URL credentials live there. The plugin reads
a path or a plain `https://` URL and nothing else, so it assumes no storage provider. To use a
private store, sync the file to a local or network path with your own tooling and point
`runtime_source` (or `runtime_dll`) at it.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `data_dir` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_DATA_DIR` | Directory holding the ledger, per-game snapshots and manifests, provisioned fork builds, and the runtime DLL. Leave unset to use the default: Documents\Gaming under your user profile. It survives plugin uninstall. Changing it after applying the mod to a game is a move of the directory, not a reconfiguration: move the old directory's contents to the new path. |
| `runtime_dll` | file | *(none)* | `CLAUDE_PLUGIN_OPTION_RUNTIME_DLL` | Path to your own legitimately obtained nvngx_dlssnr.dll (known good: version 310.8.0.0, SHA-256 E16BCF15E16E13F527491CDF7845B2FE6521A738D8F7C9C721866A8496E1FC8E). Leave unset to use runtime\nvngx_dlssnr.dll under the data directory, which setup fills from an installed DLSS 5 title or from the runtime source. The plugin names no source for this file. |
| `runtime_source` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_RUNTIME_SOURCE` | Optional local/UNC path or plain https:// URL to a copy of nvngx_dlssnr.dll that you control. The value is stored in plain text in settings.json, so it must not carry a credential: a URL with a query string is refused. For a private store, sync the file to a local path and point this at it. Every copy is hash- or signature-checked before use. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure gaming@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install gaming@<marketplace> -s <scope> --config data_dir=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "gaming@<marketplace>": {
         "options": {
           "data_dir": <value>
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

## License

MIT (SPDX-License-Identifier: MIT).
