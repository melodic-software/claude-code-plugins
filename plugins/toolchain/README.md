# toolchain

A Claude Code plugin for **polyglot build/test/lint verification**. Detect the
ecosystems a change touches and run the right build, test, and lint commands for
each, with the consuming project's own documented commands overriding portable
defaults. Five skills: four for mechanical verification of changed code, and
`/toolchain:ratchet`, which holds a count at a checked-in CI ceiling.

| Skill | Role |
|---|---|
| `/toolchain:check` | Build + test + lint for changed files, auto-detecting the affected ecosystems from git status. Also the reference skill other plugins compose for ecosystem detection and command resolution. |
| `/toolchain:check-prerequisites` | Read-only report of whether the tools the plugin declares in `prerequisites.json` resolve. Installs nothing. |
| `/toolchain:lint` | Lint + format checks only. Faster than a build cycle; `--fix` is format-only, `--code-fix` runs semantic lint autofixes behind a confirmation / `--yes` gate. |
| `/toolchain:ratchet [<counter, rule or claim>]` | Holds a count with a checked-in CI ceiling: a lint rule's violations, a suppression count, a verified performance counter, or a telemetry count. A zero count turns the rule on with no ceiling; a non-zero one is recorded at its measured value in the ceilings file CI already checks (`.performance/ratchets.json` when CI calls `ratchet.py check` with no `--file`), or in a new `.ratchets.json`, with a check step inside the required job and a same-PR or scheduled tightening plan. Counters only, never durations. It writes proposed files uncommitted and never merges. |
| `/toolchain:setup` | Configure the plugin for a repo: `check` (read-only, default) reports the effective configuration; `apply` interviews and writes the tracked config. Re-runnable. |

Each skill's `SKILL.md` is the authoritative contract for its behavior, flags, and
the ecosystem surface it currently covers. Read it there rather than a
restatement here.

## Works in any repo

Command resolution follows the marketplace-wide ecosystem-commands convention
(`docs/contracts/ecosystem-commands/README.md`; schema `ecosystem.schema.json`):
your repo's tracked `.claude/ecosystems/<ecosystem>.yaml` files are authoritative
when present, and the plugin's bundled portable defaults are the last resort.
Testing structure and commit conventions still come from your own `CLAUDE.md` and
rules. All command tables and per-ecosystem context ship inside the plugin via
`${CLAUDE_PLUGIN_ROOT}`; state and artifacts go to your project's own tree.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install toolchain@melodic-software
```

## Configuration

Ecosystem command surfaces live in tracked `.claude/ecosystems/*.yaml` files;
`/toolchain:setup apply` interviews for and persists them (`/toolchain:setup check`
reports the effective configuration).

`turn_end_result_gate` sets what happens when a turn ends on a changed tree whose
recorded result is not a pass. `/toolchain:check` and check-mode `/toolchain:lint`
record their Overall line for the tree they ran on, under the repository's git
directory (`toolchain-results/`). A Stop hook reads that record. It never runs a
build, test or lint command. A clean tree gets no warning, and neither does a turn
that changed no file and recorded no result.

| Value | At turn end |
|---|---|
| `advisory` (default) | Warns, naming each `FAIL`, `INCOMPLETE` or `STOPPED` result, or saying no result is recorded for this tree. Blocks nothing. |
| `enforce` | Warns the same way, and blocks the stop once on a recorded `FAIL`. Never blocks on `INCOMPLETE`, `STOPPED`, a missing or unreadable record, or a missing git. |
| `off` | Prints nothing. |

The option is read from your user or managed settings only, never from a
repository's settings `env` block, so a repository you work in cannot turn it off.
Any edit after a run changes the tree, so the record no longer counts.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `turn_end_result_gate` | string | `"advisory"` | `CLAUDE_PLUGIN_OPTION_TURN_END_RESULT_GATE` | What a turn end does when the tree's recorded check or lint result is not a pass: advisory (default) warns and blocks nothing, enforce also blocks once on a recorded FAIL, off stays silent. Honored from user or managed settings only. |

### How to set these

Three supported routes:

1. **Interactively.** Open this plugin's options dialog ([`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session)):
   `/plugin configure toolchain@<marketplace>`.
2. **Headless.** Save the values with [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure),
   run from the project the plugin is installed in. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin configure toolchain@<marketplace> --values-stdin < values.json
   ```

   `values.json` holds a JSON object of strings, booleans included:

   ```json
   {"turn_end_result_gate": "<value>"}
   ```

   This is the preferred headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its
   limits: the Claude Code version it needs, which install it finds, how it rejects a bad
   value, and why a session started before the change keeps the old value until a fresh
   session starts. Do **not** `claude plugin uninstall` to reconfigure: see
   [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).

   The fallback the convention names, for a Claude Code release without
   `plugin configure`, reruns the install with the new value, passing the scope
   `claude plugin list` reports for this plugin:

   ```shell
   claude plugin install toolchain@<marketplace> -s <scope> --config turn_end_result_gate=<value>
   ```

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "toolchain@<marketplace>": {
         "options": {
           "turn_end_result_gate": <value>
         }
       }
     }
   }
   ```

   The [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs)
   entry names the settings scopes Claude Code reads this key from.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself; set the value through one
of the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure): the `--values-stdin` flag's reference entry
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
