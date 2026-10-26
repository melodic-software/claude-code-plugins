# corrections

A Claude Code plugin that turns a recurring correction into a check that
enforces it. A check is only worth recording once it is proven to fail on the
mistake it targets and to pass on the current code.

| Skill | What it does |
|---|---|
| `/corrections:codify "<description>" [#PR]` | Counts how often the mistake recurs, picks the strongest enforcement-ladder rung, places the lesson by scope, and proposes a check proven with `prove-check.sh` |
| `/corrections:codify note "<observation>" [#PR \| <commit>]` | Appends one observation to the findings buffer |
| `/corrections:codify group [--since <UTC ISO-8601>]` | Reads the buffer and groups its rows by mistake, each group's count next to the threshold; writes nothing |

`codify` counts at `recurrence.min_occurrences` occurrences (default 2; set it in
`corrections.yaml` in the convention home, default `docs/conventions`, or `corrections.local.yaml`
there for yourself), or at once on a person's direct "codify this". A person's
invocation writes the proposal; a model invocation only proposes. It asks before installing any
blocking check, and reports a check whose proof did not fail on the old ref and pass on the new one as
unproven.

| Script | What it does |
|---|---|
| `scripts/prove-check.sh` | Runs a proposed check in temporary worktrees at two refs and exits 0 only when it fails at the old ref and passes at the new one |
| `scripts/codify-settings.mjs` | Prints `recurrence.min_occurrences` and the layer that set it, resolved through the config cascade (schema `schemas/corrections.schema.json`) |

## prove-check

```shell
plugins/corrections/scripts/prove-check.sh --check '<command>' --old <ref> [--new <ref>]
```

Run it from inside the repository the refs belong to. It runs `<command>`
through `bash -c` in a temporary worktree at `<old>`, which must exit
non-zero, and in one at `<new>` (default `HEAD`), which must exit 0. It prints
both exit codes, sends the check's own output to stderr, and removes both
worktrees on every exit path.

| Exit | Meaning |
|---|---|
| 0 | The proof holds: the check fails at `<old>` and passes at `<new>` |
| 1 | The proof fails: the check passes at `<old>`, or fails at `<new>` |
| 2 | Usage or environment error (bad argument, unknown ref, not a repository) |

A check that exits 126 or 127 at `<old>` counts as failing, as any non-zero
exit does, but the script warns on stderr: the command probably did not run.

Run `scripts/prove-check.test.sh` to exercise it against a fixture repository.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install corrections@melodic-software
```

## Configuration

`note` writes findings-buffer rows, under `.work/buffer/` at the repository root by default,
gitignored. No network.

The two `findings_buffer_adapter_*` options bind one repository's own findings-buffer adapter, in
user scope, where a repository cannot write. `buffer.sh` reads them from your user settings and
managed settings only, never from the environment or a session's `--settings` file, so the
environment-variable column and the `--settings` route in the generated block below do not apply
to them. A plugin loaded outside the plugin cache (`--plugin-dir`) has no user settings to read,
so there only managed settings can set them.
`findings_buffer_adapter_repository` is that
repository's git common directory (`git rev-parse --path-format=absolute --git-common-dir` in its
main checkout) and `findings_buffer_adapter_path` the adapter directory relative to the checkout
root. The binding applies in that repository's main checkout and its worktrees, and in no other
repository, even one with the same layout, and wins over the repository's own binding file. The
adapter must resolve inside the current checkout, outside any repository nested in it. The
repository's `findings-buffer.yaml` and `findings-buffer.local.yaml` still name only adapters the
plugin ships. See `tools/findings-buffer/CONTRACT.md` "Core".

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `findings_buffer_adapter_repository` | directory | *(none)* | `CLAUDE_PLUGIN_OPTION_FINDINGS_BUFFER_ADAPTER_REPOSITORY` | Git common directory (git rev-parse --path-format=absolute --git-common-dir) of the one repository whose own findings-buffer adapter you trust. Applies in that repository's checkout and worktrees only. Unset: only adapters the plugin ships run. |
| `findings_buffer_adapter_path` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_FINDINGS_BUFFER_ADAPTER_PATH` | That repository's adapter directory, relative to the checkout root, holding executable append.sh and read.sh and a capabilities.json with schema_version 1.x. Set both options or neither. A path out of the checkout or into a nested repository is refused. |

### How to set these

Three supported routes:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure corrections@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install corrections@<marketplace> -s <scope> --config findings_buffer_adapter_repository=<value>
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
       "corrections@<marketplace>": {
         "options": {
           "findings_buffer_adapter_repository": <value>
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

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
