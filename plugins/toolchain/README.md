# toolchain

A Claude Code plugin for **polyglot build/test/lint verification**. Detect the
ecosystems a change touches and run the right build, test, and lint commands for
each, running only the commands the consuming project records or its build files
imply. Four skills: three for mechanical verification of changed code, and
`/toolchain:ratchet`, which holds a count at a checked-in CI ceiling.

| Skill | Role |
|---|---|
| `/toolchain:check` | Build + test + lint for changed files, auto-detecting the affected ecosystems from git status. Also the reference skill other plugins compose for ecosystem detection and command resolution. |
| `/toolchain:lint` | Lint + format checks only. Faster than a build cycle; `--fix` is format-only, `--code-fix` runs semantic lint autofixes behind a confirmation / `--yes` gate. |
| `/toolchain:ratchet [<counter, rule or claim>]` | Holds a count with a checked-in CI ceiling: a lint rule's violations, a suppression count, a verified performance counter, or a telemetry count. A zero count turns the rule on with no ceiling; a non-zero one is recorded at its measured value in the ceilings file CI already checks (`.performance/ratchets.json` when CI calls `ratchet.py check` with no `--file`), or in a new `.ratchets.json`, with a check step inside the required job and a same-PR or scheduled tightening plan. Counters only, never durations. It writes proposed files uncommitted and never merges. |
| `/toolchain:setup` | Configure the plugin for a repo: `check` (read-only, default) reports the effective configuration; `apply` interviews and writes the tracked config. Re-runnable. |

Each skill's `SKILL.md` is the authoritative contract for its behavior, flags, and
the ecosystem surface it currently covers. Read it there rather than a
restatement here.

## Works in any repo

Command resolution follows the marketplace-wide ecosystem-commands convention
(`docs/contracts/ecosystem-commands/README.md`; schema `ecosystem.schema.json`):
your repo's tracked `docs/conventions/ecosystems/<ecosystem>.yaml` files are authoritative
when present; otherwise an attended run infers commands from your build files or
asks. The plugin ships no default command. An unattended run (`--unattended`, a
headless or lane run, or one that cannot tell whether a person is present) runs
only a recorded, stated or inferred command. Either kind of run reports a key
nothing resolves as `skip (unresolved: ...)`. Testing structure and commit
conventions still come from your own `CLAUDE.md` and rules. State and artifacts
go to your project's own tree.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install toolchain@melodic-software
```

## Configuration

Ecosystem command surfaces live in tracked `docs/conventions/ecosystems/*.yaml` files;
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

`result_gate_enabled` (default `true`) turns the Stop hook itself on or off. The hook
runs only while it is `true` and `turn_end_result_gate` is not `off`; while it runs,
`turn_end_result_gate` picks `advisory` or `enforce`. The boolean sits beside the
string rather than replacing its `off`, so no existing setting changes meaning. The
hook resolves it through the shared helper as a security control
([hook enablement](../../docs/contracts/hook-enablement/README.md#the-per-hook-setting)),
which keeps the guarantee above: a repository can turn the hook on but never off.
Only a `false` in your user settings' `pluginConfigs`, or in managed settings, turns
it off; a `CLAUDE_PLUGIN_OPTION_RESULT_GATE_ENABLED=false` in the environment is
ignored.

Reading the setting costs processes on every Stop where `turn_end_result_gate` is not
`off`, before the hook's own `git` calls: `bash` for the helper, which starts `uname`,
then `jq` when the install's `settings.json` exists, and one `jq` per managed settings
file (on Linux, plus two `stat` each)
([hook budget](../../docs/contracts/hook-budget/README.md#the-hook-enablement-helper)).
No wall-clock figure in S has been taken for this hook.

A repository can commit `toolchain.yaml` in its convention home (default
`docs/conventions`) to set this key, checked against
[`schemas/toolchain.schema.json`](schemas/toolchain.schema.json):

| Key | Values | Default | What it controls |
|---|---|---|---|
| `result_gate_enabled` | `true`, `false` | `true` | Whether the turn-end Stop hook runs for contributors who have not set their own value. Only `true` takes effect; a `false` here is ignored. |

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `result_gate_enabled` | boolean | `true` | Run the turn-end Stop hook that checks the tree's recorded check or lint result. On by default. A repository's toolchain.yaml can turn it on but not off; only your user or managed settings turn it off. While it is on, turn_end_result_gate picks what it does. |
| `turn_end_result_gate` | string | `"advisory"` | What a turn end does when the tree's recorded check or lint result is not a pass: advisory (default) warns and blocks nothing, enforce also blocks once on a recorded FAIL, off stays silent. Honored from user or managed settings only. |
| `ratchet_break_glass` | boolean | `false` | When on, /toolchain:ratchet writes break_glass true into a ceilings file lacking the key, so a per-file counter honors inline exceptions with a reason, expiry and approver. Defaults to false, which writes false. The file's own break_glass key wins over this option. |

### How to set these

Set the options above for `toolchain@<marketplace>`, replacing `<marketplace>` with the
marketplace you installed this plugin from:

- **In a session or headless:** [`/plugin` in a session](https://code.claude.com/docs/en/plugins/cli-reference#plugin-in-a-session) or
  [`claude plugin configure`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure). The configure command is the preferred
  headless route in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/contracts/plugin-reconfiguration/README.md), which records its limits.
- **By hand:** under [`pluginConfigs`](https://code.claude.com/docs/en/settings-reference#pluginconfigs) in your **user** settings.

Do **not** uninstall the plugin to reconfigure it: see [What an uninstall deletes and keeps](https://code.claude.com/docs/en/plugins/cli-reference#what-an-uninstall-deletes-and-keeps).
For a Claude Code release without `plugin configure`, see [Plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install).

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration)
- [Plugin configure](https://code.claude.com/docs/en/plugins/cli-reference#plugin-configure)
- [Plugin install options](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills)
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect)
- [Manage installed plugins](https://code.claude.com/docs/en/plugins/install#manage-installed-plugins)

<!-- END GENERATED: plugin options -->

## License

MIT (SPDX-License-Identifier: MIT).
