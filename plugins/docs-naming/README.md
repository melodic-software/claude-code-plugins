# docs-naming

A Claude Code plugin that plans, applies, and enforces a file-name casing rule
across a tracked tree. One concern: the names of files, and the references that
break when a name changes. The post-rename sweep for a rename someone already
made is `/docs-hygiene:rename-references`, the sibling in the `docs-hygiene`
plugin.

## The skills

| Skill | What it does |
|---|---|
| `/docs-naming:setup` | Check-centric setup for the plugin's one consumer config file, `docs/conventions/docs-naming.yaml`: `check` resolves all three layers, names the layer behind every key, and verifies that the casing regex compiles, each tier names a known form, each generated file's regenerator resolves, the team layer is tracked, and the personal override is ignored; `apply` writes the team layer per key, idempotently. |
| `/docs-naming:audit-file-names` | Read-only inventory of a tree's file names against the configured casing rule: proposes a legal name per offender, finds every reference to each one, classifies each site by shape and by the tier its file belongs to, refuses any plan that would create a case-only path collision, and writes the rename plan the realign stage consumes. Renames nothing and edits nothing. |
| `/docs-naming:realign-file-names` | Executes that plan one file at a time, behind one human acceptance each: `git mv`, then only the reference shapes the citing file's tier allows, then the declared regenerator for any generated record. Refuses a blanket yes, a range, a glob, and `all`. Frozen and ambiguous sites are listed and left alone. Never commits and never bumps a version. |
| `/docs-naming:generate-file-name-gate` | Emits the check that enforces the rule: a standalone bash checker plus its own suite, with the rule, roots, and exemptions inlined from the resolved configuration, carrying no run-time dependency on this plugin. `--rule` also writes the path-scoped rule file. A rule alone cannot enforce a naming convention: it only guides Claude during a session, blocks nothing, and never runs in CI. |

## Requirements

- **Bash + git + jq**. Ambient skill mechanics (Git Bash on native Windows;
  the skills' scripts strip CRLF and avoid Windows-hostile constructs). `jq`
  reads the configuration layers; `/docs-naming:setup check` reports a missing
  one as FAIL.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install docs-naming@melodic-software
```

## Configuration

The skills read one consumer surface, layered as `userConfig` (the plugin's
`file_names` option, a JSON object of your own `file_names` keys), team
(`docs/conventions/docs-naming.yaml`, tracked, validated by
[`schemas/docs-naming.schema.json`](schemas/docs-naming.schema.json)), and a
gitignored personal override (`docs/conventions/docs-naming.local.yaml`). All
three absent is a valid state: every key has a bundled default, and the defaults
are this marketplace's own values, except `generated`, which is empty.
`/docs-naming:setup check` verifies the
resolved document and names the layer that supplied each key, and
`/docs-naming:setup apply` writes the team layer and nothing else, never the
consumer's `.gitignore`. Keys, defaults, merge classes, and the policy floor are
documented in [`reference/config.md`](reference/config.md).

The JSON files under `.claude/` the team layer and personal override used to live in
(`docs-naming.json`, `docs-naming.local.json`, and their `docs-hygiene` names)
are not read. `/docs-naming:setup check` names each one it finds, and while the
team YAML is absent `/docs-naming:setup apply` copies the old team file's keys
into it.

The user-global files `~/.claude/docs-naming.json` and
`~/.claude/docs-hygiene.json` are retired in favor of the `file_names` option.
While the option is unset or invalid, the first of them that exists is still read, and
every run warns about each one. `/docs-naming:setup check` names them, and
`/docs-naming:setup apply` previews copying their keys into the option and gives
the command that saves it. The options reference below says how to set the
option.

This plugin still reads, or reports as retired, the `.claude/` paths named here; until the plugin migrates, keep config where this page says it is read, then move it where [config locations](reference/config-locations.md) says.

## Renames are gated per file

`realign-file-names` accepts one file at a time. The findings artifact does not
declare `type: review-findings`, because that type is auto-applicable by
construction and every rename here moves a tracked file behind one human
acceptance. The artifact contract is
[`context/file-name-findings.md`](context/file-name-findings.md).

## Renaming files: what the plugin does not do for you

`audit-file-names` plans, `realign-file-names` applies one acceptance at a time,
and `generate-file-name-gate` emits the check that keeps the tree from drifting
back. Three things stay with the operator on purpose:

- **The version bump and the changelog entry.** A renamed file inside a
  versioned unit usually needs both (or a changelog fragment, where the project
  releases from fragments), and the shape of each is the consuming project's
  release convention. The realign never edits either.
- **The commit.** The realign leaves the working tree uncommitted so the diff
  gets read before it is recorded. A rename sweep is exactly the change that
  deserves that.
- **Wiring the emitted gate.** The emitter names the CI step, the registry row,
  and the decision record it does not write, and writes none of them.

**Cross-platform verification.** The case-only `git mv` path cannot be observed
on a case-sensitive filesystem, so it is exercised on Windows by this
repository's `test-windows` CI lane, which runs the bundled suites. macOS is
unverified; the scripts avoid the constructs that differ there (no `${x,,}`, no
`sed -i`, existence asked of the git index rather than the filesystem), but no
runner covers it.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. For how Claude Code asks for
these and hands them to the plugin, see [User configuration](https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration).

| Option | Type | Default | Description |
| --- | --- | --- | --- |
| `file_names` | string | *(none)* | Your file_names keys as one JSON object, the shape of docs/conventions/docs-naming.yaml, e.g. {"exempt_basenames":\["NOTES.md"\]}. Empty (default): none. Repository files win; on policy-floor keys it only adds, and generated is ignored. Invalid JSON is reported and ignored. |

### How to set these

Set the options above for `docs-naming@<marketplace>`, replacing `<marketplace>` with the
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
