# formal-verification

Formal verification for the part of a codebase where a bug costs most and tests reach least.
`/formal-verification:chart` checks a TLA+ model with TLC, draws its states as a Mermaid chart, and
gives the shortest path to each rule that breaks, for a person to judge. A consumer keeps each model
in its own `formal-<area>` skill, shaped by [`reference/formal-skill.md`](reference/formal-skill.md).

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install formal-verification@melodic-software
```

## Skills

| Skill | What it does |
|---|---|
| `/formal-verification:chart` | Model-checks a TLA+ spec with TLC and writes `chart.mmd` and `report.md`: each rule that holds, each that breaks with its shortest path, and the rules a bound left unchecked. Model-invoked too, so a `formal-<area>` skill's Run can call it. |
| `/formal-verification:setup` | `check` reports the script runtime, Java, the model checker and the renderer; `apply install-model-checker` and `apply install-renderer` download the pinned file into the plugin data directory and keep it only when its checksum matches. Typed only. |

## Configuration

Machine paths are plugin options, set through `/plugin configure`: the model checker jar, the Java
binary and the script runtime (the options block below).

Version pins and default bounds are keys in the consumer's
`docs/conventions/formal-verification.yaml`, checked against
[`schemas/formal-verification.schema.json`](schemas/formal-verification.schema.json). An absent key
takes the shipped value in [`defaults.json`](defaults.json). Download URLs and checksums are not
settings: they live only in [`releases.json`](releases.json), and a version chosen in the
convention file must have an entry there. `scripts/settings.mjs` prints the
resolved values:

```shell
node <plugin root>/scripts/settings.mjs --project-dir .
```

A bound for one model goes in that model's run command (`--chart-states`, `--rerun-states`), in its
`formal-<area>` skill.

## Prerequisites

| Tool | Who installs it |
|---|---|
| A script runtime: Node, Bun or Deno (the launcher names the versions it accepts) | You. |
| Java (the `java.min_version` setting) | You. The plugin never installs Java. |
| The TLC model checker, `tla2tools.jar` | `/formal-verification:setup apply install-model-checker`, on your typed request, from the pinned URL and SHA-256. Or point the model checker jar option at your own. |
| The Pele renderer, only for an image of a chart | `/formal-verification:setup apply install-renderer`, from the pinned tarball and integrity string. |

No script installs anything while a skill runs, and an unattended run that finds the toolchain
missing reports `blocked: toolchain missing` and stops. `prerequisites.json` declares the runtime,
Java and the renderer for `/harness-ops:prerequisites`; the jar is a file in the plugin data
directory, which that checker has no kind for, so `scripts/toolchain.mjs check` checks it.

## Tests

`node --test scripts/toolchain.test.mjs` covers settings resolution and the toolchain check and
install. The chart scripts carry their own suite under `skills/chart/scripts/test/`.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `model_checker_jar` | file | *(none)* | Path to tla2tools.jar, the TLC model checker. Unset uses the jar that setup installs under the plugin data directory. |
| `java` | file | *(none)* | Path to the java binary that runs TLC. Unset uses java on PATH. The plugin never installs Java. |
| `script_runtime` | file | *(none)* | Path to the Node, Bun or Deno binary that runs the chart scripts. Unset lets the launcher pick the first supported one on PATH. |

### How to set these

Set the options above for `formal-verification@<marketplace>`, replacing `<marketplace>` with the
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

## Attribution

`/formal-verification:chart` carries the `statechart` skill of pstack in
[cursor/plugins](https://github.com/cursor/plugins), its text and its scripts, changed so that the
scripts take the jar, Java and bounds as arguments and install nothing. The record is
[`docs/upstream/cursor-pstack.md`](../../docs/upstream/cursor-pstack.md). Those files are used under
this license:

```text
MIT License

Copyright (c) 2026 Lauren Tan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
