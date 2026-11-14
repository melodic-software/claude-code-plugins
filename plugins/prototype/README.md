# prototype

A Claude Code plugin for settling one design question with **code written to be deleted**, before
you commit to an architecture. A prototype shows cheaply that "X works like THIS": you drive a
model by hand or step between layouts, write the answer down, and delete the code.

It ships **three skills**, one per kind of question:

- `pressure-test`, invoked as `/prototype:pressure-test [observe] <scope>`. Answers "Does this state machine / data model / API surface hold up?" A portable logic module you can lift into production, driven by hand from a disposable shell: a terminal app by default, or a self-contained HTML demo that someone outside engineering operates by clicking buttons. With `observe`, the agent runs each variant of a fork a run can settle, records behavior, output and unqualified timing per variant, and recommends one; product and preference calls stay with you. |
- `explore-directions`, invoked as `/prototype:explore-directions <scope>`. Answers "What should this look like?" A few structurally different layouts (three by default), toggled from a floating switcher, as a self-contained HTML mockup by default or on the real stack behind one route on request. For the mockup it also tells you that you can run `/design`, the bundled `design` skill's editable canvas, yourself. |
- `build-generator`, invoked as `/prototype:build-generator <the thing you're stuck on>`. Answers "Prompting keeps landing close but not quite." A throwaway generating tool with live controls bound to the taste values, or a replica of the process behind a reference; you tune it, its saved output goes into the project, and the tool is deleted. You invoke it; the model never does. |

All three follow the six rules in `context/discipline.md`, from "Starts with one command" to
"Delete or absorb when done", and all three write the validated answer into a durable note before
the code is deleted. `build-generator` has one exception there: its tool and saved config live in
the project while you tune.

## When to use which

- **Logic** is a behavioral or feasibility spike: the open question concerns data shape, state
  transitions, or business rules. The result is a **pure logic module** behind a disposable shell;
  once the question is answered, the module moves into production and the shell is deleted.
- **UI** is a design prototype: the open question is how something should look. The variants
  differ in structure, not only in color, so you can compare them side by side, then merge the
  winner into the page it belongs to.

`pressure-test` and `explore-directions` auto-invoke on their own trigger phrases, or you can call
them directly; `build-generator` runs only when you invoke it. If you're not sure
which fits, a backend/logic question routes to `pressure-test` and a page/component question routes to `explore-directions`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install prototype@melodic-software
```

## Configuration

One setting, `level`, sets how large an `explore-directions` run is: `sketch`, `standard` (the
default) or `full`, or a level your repository adds. Set it per user in the plugin's `userConfig`,
per repository in `docs/conventions/prototype.yaml`, or per run by asking ("the full package") or
with `--level <name>`. Every key, layer and value is in
[`reference/config.md`](reference/config.md). The other inputs are conversational: the scope you
pass, the `observe` option for `pressure-test`, and a variant count you ask for. It reads your
project's own stack and
conventions rather than imposing its own. It writes throwaway code next to where your production
code lives, except its HTML pages (the default UI mockup and the HTML logic demo), which go in a
temp directory outside the repository. `build-generator` saves its configuration as a JSON file
in the project, which stays as the output after the tool is deleted.

## Requirements

- **Bash** for the bundled ecosystem-detection script. On native Windows,
  install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  it runs under Git Bash. Without Bash, detection reports "none detected" and
  the skills read the host project directly to pick the stack.

Prototypes are built in whatever language and task runner your host project
already uses; the plugin adds no runtime of its own.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `level` | string | *(none)* | The level a /prototype:explore-directions run takes when the request names none: sketch, standard or full, or a level your repository's docs/conventions/prototype.yaml adds. Unset is standard. A repository's prototype.yaml wins over this option; see the plugin's reference/config.md. |

### How to set these

Set the options above for `prototype@<marketplace>`, replacing `<marketplace>` with the
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
